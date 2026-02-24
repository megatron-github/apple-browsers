//
//  PromoService.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Combine
import Foundation
import os.log

/// Tracks state for a promo that is currently being shown.
struct ActiveShowSession {
    let promoId: String
    let delegate: any PromoDelegate
    let promoType: PromoType

    /// First-write-wins flag. Once true, ignore further results from show(), timeout, or eligibility.
    var isResultRecorded = false

    /// Task that awaits delegate.show() and records the result. Cancelled when session is cleaned up.
    var showTask: Task<Void, Never>?

    /// Task that sleeps for promoType.timeoutInterval. On fire, records timeoutResult if !isResultRecorded.
    var timeoutTask: Task<Void, Never>?

    /// Subscription to isEligiblePublisher. On false, calls hide() so the promo resumes with its chosen result; the result flows through handleShowResult.
    var eligibilityCancellable: AnyCancellable?
}

@MainActor
final class PromoService {

    // MARK: - Public

    /// Currently visible promos.
    var visiblePromosPublisher: AnyPublisher<[Promo], Never> {
        visiblePromoIds
            .map { [weak self] ids in
                ids.compactMap { id in self?.promos.first { $0.id == id } }
            }
            .eraseToAnyPublisher()
    }

    /// Manually dismiss a promo by ID.
    func dismiss(promoId: String, result: PromoResult) {
        if activeSessions[promoId] != nil {
            recordResultAndCleanup(promoId: promoId, result: result)
        } else {
            updateHistoryForDismissedPromo(promoId: promoId, result: result)
        }
    }

    /// Reverse a dismissal. clearHistory resets timesDismissed/lastDismissed as well.
    func undismiss(promoId: String, clearHistory: Bool) {
        var record = historyStore.record(for: promoId)
        record.nextEligibleDate = nil
        if clearHistory {
            record.timesDismissed = 0
            record.lastDismissed = nil
        }
        historyStore.save(record)
    }

    /// Debug: simulated "now" for cooldown and eligibility checks. Set by debug menus when advancing time.
    /// In-memory only; nil in production.
    var debugSimulatedDate: Date?

    /// Clears debug date override and all promo history. For debug reset.
    func resetDebugState() {
        debugSimulatedDate = nil
        for (_, session) in activeSessions {
            session.showTask?.cancel()
            session.timeoutTask?.cancel()
            session.eligibilityCancellable?.cancel()
            session.delegate.hide()
        }
        activeSessions.removeAll()
        visiblePromoIds.send([])
        historyStore.resetAll()
    }

    /// Notifies that the app was activated by an external source (e.g. deep link). Suppresses promos for a short window.
    func notifyExternalActivation() {
        isExternallyActivated = true
        externalActivationClearTask?.cancel()
        externalActivationClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.externalActivationWindow * 1_000_000_000))
            self?.isExternallyActivated = false
        }
    }

    /// Defers trigger evaluation for a short window after app activation, giving the URL event handler time to deliver its Apple Event and set the external activation flag.
    func deferEvaluation() {
        isEvaluationDeferred = true
        deferralTask?.cancel()
        deferralTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.evaluationDeferralWindow * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.processTriggersAfterExternalActivationCheck()
        }
    }

    /// Attaches a delegate to a promo by ID. Call when the delegate object is ready.
    /// If all delegates are ready and start() was already called, completes registration immediately.
    func setDelegate(for promoId: String, delegate: any PromoDelegate) {
        guard let index = promos.firstIndex(where: { $0.id == promoId }) else {
            Logger.general.warning("PromoService: unknown promo ID \(promoId)")
            return
        }
        promos[index].delegate = delegate

        if isStarted && !isRegistrationLocked && allDelegatesReady {
            completeRegistration()
        }
    }

    /// Begins evaluation. If all delegates are ready, evaluation starts immediately.
    /// Otherwise, starts a fallback timeout (1s) after which evaluation begins with available delegates.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        if allDelegatesReady {
            completeRegistration()
            return
        }

        registrationTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.registrationFallbackTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.completeRegistration()
        }
    }

    // MARK: - Internal state

    private static let externalActivationWindow: TimeInterval = 5.0
    private static let registrationFallbackTimeout: TimeInterval = 1.0
    /// Grace period after app activation during which trigger evaluation is deferred, giving the URL event handler time to set its external activation flag.
    private static let evaluationDeferralWindow: TimeInterval = 0.5

    /// Fixed list of promos (array order = priority order). Delegates attached via setDelegate(for:delegate:).
    private var promos: [Promo]
    private var isStarted = false
    /// After registration completes, evaluation begins.
    private var isRegistrationLocked = false
    private var registrationTimeoutTask: Task<Void, Never>?
    private let historyStore: PromoHistoryStoring
    private let triggerPublisher: AnyPublisher<PromoTrigger, Never>

    /// Suppresses all promos when true. Set by URL event handler on external activation, cleared after a delay.
    private var isExternallyActivated = false
    private var externalActivationClearTask: Task<Void, Never>?

    /// Defers trigger evaluation when true, to allow time to receive the Apple URL event.
    /// Set by URL event handler on activation, cleared after a delay when deferred evaluation runs.
    private var isEvaluationDeferred = false
    private var deferralTask: Task<Void, Never>?

    private var activeSessions: [String: ActiveShowSession] = [:]
    private let visiblePromoIds: CurrentValueSubject<Set<String>, Never>
    private var cancellables = Set<AnyCancellable>()

    /// Triggers to be evaluated after a delay.
    private var bufferedTriggers = Set<PromoTrigger>()

    private let evaluationQueue = DispatchQueue(label: "com.duckduckgo.promoService.evaluation")

    private var currentDate: Date {
        debugSimulatedDate ?? Date()
    }

    /// True when every promo in promos has a non-nil delegate.
    private var allDelegatesReady: Bool {
        promos.allSatisfy { $0.delegate != nil }
    }

    // MARK: - Init

    init(
        promos: [Promo],
        historyStore: PromoHistoryStoring,
        isExternalLaunch: Bool,
        triggerPublisher: AnyPublisher<PromoTrigger, Never>
    ) {
        self.promos = promos
        self.historyStore = historyStore
        self.triggerPublisher = triggerPublisher
        self.visiblePromoIds = CurrentValueSubject([])

        if isExternalLaunch {
            notifyExternalActivation()
        }

        visiblePromoIds
            .dropFirst()
            .sink { [weak self] ids in
                self?.historyStore.saveVisiblePromoIds(ids)
            }
            .store(in: &cancellables)

        triggerPublisher
            .receive(on: evaluationQueue)
            .sink { [weak self] trigger in
                Task { @MainActor in
                    guard let self else { return }
                    if !self.isRegistrationLocked || self.isEvaluationDeferred {
                        self.bufferedTriggers.insert(trigger)
                    } else {
                        await self.evaluateTrigger(trigger)
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func completeRegistration() {
        guard !isRegistrationLocked else { return }
        isRegistrationLocked = true
        registrationTimeoutTask?.cancel()
        registrationTimeoutTask = nil

        processTriggersAfterRegistrationLocks()
        restoreVisiblePromos()
    }

    private func processTriggersAfterRegistrationLocks() {
        let buffered = bufferedTriggers
        bufferedTriggers.removeAll()
        guard !buffered.isEmpty, !isExternallyActivated else { return }

        for promo in promos {
            guard let delegate = promo.delegate else { continue }
            guard !promo.triggers.isDisjoint(with: buffered) else { continue }

            delegate.refreshEligibility()
            let passesRules = checkRules(for: promo)
            guard passesRules else { continue }

            let record = historyStore.record(for: promo.id)
            guard !record.isPermanentlyDismissed, record.isEligible(asOf: currentDate) else { continue }
            guard delegate.isEligible else { continue }

            performShow(promo: promo, delegate: delegate, record: record, isRestore: false)
        }
    }

    private func processTriggersAfterExternalActivationCheck() async {
        isEvaluationDeferred = false
        let buffered = bufferedTriggers
        bufferedTriggers.removeAll()
        guard !buffered.isEmpty else { return }
        guard !isExternallyActivated else { return }

        for trigger in buffered {
            await evaluateTrigger(trigger)
        }
    }

    // MARK: - Restore on restart

    private func restoreVisiblePromos() {
        guard !isExternallyActivated else { return }
        let persistedIds = historyStore.loadVisiblePromoIds()
        guard !persistedIds.isEmpty else { return }

        for promoId in persistedIds {
            guard let promo = promos.first(where: { $0.id == promoId }),
                  let delegate = promo.delegate else { continue }
            delegate.refreshEligibility()
            let record = historyStore.record(for: promoId)
            guard !record.isPermanentlyDismissed, record.isEligible(asOf: currentDate) else { continue }
            guard delegate.isEligible else { continue }

            performShow(promo: promo, delegate: delegate, record: record, isRestore: true)
        }
    }

    // MARK: - Trigger handling

    private func evaluateTrigger(_ trigger: PromoTrigger) async {
        let matchingPromos = promos.filter { $0.triggers.contains(trigger) }
        matchingPromos.forEach { $0.delegate?.refreshEligibility() }

        for promo in matchingPromos {
            guard let delegate = promo.delegate else { continue }
            let passesRules = checkRules(for: promo)
            guard passesRules else { continue }

            let record = historyStore.record(for: promo.id)
            guard !record.isPermanentlyDismissed, record.isEligible(asOf: currentDate) else { continue }
            guard delegate.isEligible else { continue }

            performShow(promo: promo, delegate: delegate, record: record, isRestore: false)
            return
        }
    }

    // MARK: - Step 1: Rules

    private func checkRules(for promo: Promo) -> Bool {
        if promo.promoType.severity == .low { return true }
        if isExternallyActivated { return false }

        let visibleIds = visiblePromoIds.value
        let promoId = promo.id
        let severity = promo.promoType.severity
        let context = promo.context
        let coexisting = promo.coexistingPromoIDs

        for otherId in visibleIds where otherId != promoId {
            guard let other = promos.first(where: { $0.id == otherId }) else { continue }
            let mutuallyCoexisting = coexisting.contains(otherId) && other.coexistingPromoIDs.contains(promoId)

            let contextConflict = !mutuallyCoexisting && (
                context == .global || other.context == .global || context == other.context
            )
            if contextConflict { return false }

            if severity >= .medium && other.promoType.severity >= .medium && !mutuallyCoexisting {
                return false
            }
        }

        if promo.respectsGlobalCooldown && severity >= .medium {
            let cooldownHours = promo.initiated.cooldownHours
            let cooldownInterval = TimeInterval(cooldownHours * 3600)
            let lastDismissedForType = promos
                .filter { $0.initiated == promo.initiated && $0.setsGlobalCooldown }
                .compactMap { historyStore.record(for: $0.id).lastDismissed }
                .max()
            if let last = lastDismissedForType, currentDate.timeIntervalSince(last) < cooldownInterval {
                return false
            }
        }

        return true
    }

    // MARK: - Perform show

    private func performShow(promo: Promo, delegate: any PromoDelegate, record: PromoHistoryRecord, isRestore: Bool = false) {
        let promoId = promo.id
        let recordToUse = record

        let eligibilityCancellable = delegate.isEligiblePublisher
            .dropFirst()
            .sink { [weak self] eligible in
                guard !eligible else { return }
                Task { @MainActor in
                    self?.handleEligibilityLost(promoId: promoId)
                }
            }

        var timeoutTask: Task<Void, Never>?
        if let interval = promo.promoType.timeoutInterval {
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                await MainActor.run {
                    self?.handleTimeout(promoId: promoId)
                }
            }
        }

        let showTask = Task { [weak self] in
            let result = await delegate.show(history: recordToUse)
            await MainActor.run {
                self?.handleShowResult(promoId: promoId, result: result)
            }
        }

        var session = ActiveShowSession(
            promoId: promoId,
            delegate: delegate,
            promoType: promo.promoType,
            isResultRecorded: false,
            showTask: showTask,
            timeoutTask: timeoutTask,
            eligibilityCancellable: eligibilityCancellable
        )
        activeSessions[promoId] = session
        visiblePromoIds.send(Set(activeSessions.keys))
    }

    // MARK: - Result handling

    private func handleShowResult(promoId: String, result: PromoResult) {
        recordResultAndCleanup(promoId: promoId, result: result)
    }

    private func handleTimeout(promoId: String) {
        guard let session = activeSessions[promoId] else { return }
        recordResultAndCleanup(promoId: promoId, result: session.promoType.timeoutResult)
    }

    private func handleEligibilityLost(promoId: String) {
        guard let session = activeSessions[promoId], !session.isResultRecorded else { return }
        session.delegate.hide()
    }

    private func recordResultAndCleanup(promoId: String, result: PromoResult) {
        guard var session = activeSessions[promoId] else { return }
        if session.isResultRecorded { return }

        session.isResultRecorded = true
        activeSessions[promoId] = session

        session.showTask?.cancel()
        session.showTask = nil
        session.timeoutTask?.cancel()
        session.timeoutTask = nil
        session.eligibilityCancellable?.cancel()
        session.eligibilityCancellable = nil

        switch result {
        case .actioned, .ignored(cooldown: nil):
            var record = historyStore.record(for: promoId)
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = .distantFuture
            historyStore.save(record)
        case .ignored(cooldown: let interval?):
            var record = historyStore.record(for: promoId)
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = currentDate.addingTimeInterval(interval)
            historyStore.save(record)
        case .none:
            break
        }

        activeSessions.removeValue(forKey: promoId)
        visiblePromoIds.send(Set(activeSessions.keys))

        session.delegate.hide()
    }

    private func updateHistoryForDismissedPromo(promoId: String, result: PromoResult) {
        var record = historyStore.record(for: promoId)
        switch result {
        case .actioned, .ignored(cooldown: nil):
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = .distantFuture
            historyStore.save(record)
        case .ignored(cooldown: let interval?):
            record.timesDismissed += 1
            record.lastDismissed = currentDate
            record.nextEligibleDate = currentDate.addingTimeInterval(interval)
            historyStore.save(record)
        case .none:
            break
        }
    }
}

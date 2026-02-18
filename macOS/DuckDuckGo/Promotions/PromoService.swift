//
//  PromoService.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

/// Tracks state for a promo that is currently being shown.
struct ActiveShowSession {
    /// The promo currently being shown.
    let promo: any Promo

    /// First-write-wins flag. Once true, ignore further results from show(), timeout, or eligibility.
    var isResultRecorded = false

    /// Task that awaits promo.show() and records the result. Cancelled when session is cleaned up.
    var showTask: Task<Void, Never>?

    /// Task that sleeps for promoType.timeoutInterval. On fire, records timeoutResult if !isResultRecorded.
    var timeoutTask: Task<Void, Never>?

    /// Subscription to isEligiblePublisher. On false, hides and records .none if !isResultRecorded.
    var eligibilityCancellable: AnyCancellable?
}

@MainActor
final class PromoService {

    // MARK: - Public

    /// Currently visible promos.
    var visiblePromosPublisher: AnyPublisher<[any Promo], Never> {
        visiblePromoIds
            .map { [weak self] ids in
                ids.compactMap { id in self?.promos.first { $0.id == id } }
            }
            .eraseToAnyPublisher()
    }

    /// Manually dismiss a promo by ID.
    func dismiss(promoId: String, result: PromoResult) {
        if let _ = activeSessions[promoId] {
            recordResultAndCleanup(promoId: promoId, result: result)
        } else {
            updateHistoryForDismissedPromo(promoId: promoId, result: result)
        }
    }

    /// Reverse a dismissal. clearHistory resets timesPresented/lastPresented as well.
    func undismiss(promoId: String, clearHistory: Bool) {
        var record = historyStore.record(for: promoId)
        record.nextEligibleDate = nil
        if clearHistory {
            record.timesPresented = 0
            record.lastPresented = nil
        }
        historyStore.save(record)
    }

    // MARK: - Internal state

    private let promos: [any Promo]
    private let historyStore: PromoHistoryStoring
    private let isExternalLaunch: Bool
    private let nextStepsPromoIds: Set<String>

    private var activeSessions: [String: ActiveShowSession] = [:]
    private let visiblePromoIds: CurrentValueSubject<Set<String>, Never>
    private var lastInitiatedShow: [PromoInitiated: Date] = [:]
    private var cancellables = Set<AnyCancellable>()

    private let evaluationQueue = DispatchQueue(label: "com.duckduckgo.promoService.evaluation")

    // MARK: - Init

    init(
        promos: [any Promo],
        historyStore: PromoHistoryStoring,
        isExternalLaunch: Bool,
        triggerPublisher: AnyPublisher<PromoTrigger, Never>,
        nextStepsPromoIds: Set<String> = []
    ) {
        self.promos = promos
        self.historyStore = historyStore
        self.isExternalLaunch = isExternalLaunch
        self.nextStepsPromoIds = nextStepsPromoIds
        self.visiblePromoIds = CurrentValueSubject([])

        triggerPublisher
            .receive(on: evaluationQueue)
            .sink { [weak self] trigger in
                Task { @MainActor in
                    await self?.evaluateTrigger(trigger)
                }
            }
            .store(in: &cancellables)

        visiblePromoIds
            .dropFirst()
            .sink { [weak self] ids in
                self?.historyStore.saveVisiblePromoIds(ids)
            }
            .store(in: &cancellables)

        restoreVisiblePromos()
    }

    // MARK: - Restore on restart

    private func restoreVisiblePromos() {
        guard !isExternalLaunch else { return }
        let persistedIds = historyStore.loadVisiblePromoIds()
        guard !persistedIds.isEmpty else { return }

        for promoId in persistedIds {
            guard let promo = promos.first(where: { $0.id == promoId }) else { continue }
            let record = historyStore.record(for: promoId)
            guard !record.isPermanentlyDismissed, record.isEligible else { continue }
            guard promo.isEligible else { continue }

            performShow(promo: promo, record: record, isRestore: true)
        }
    }

    // MARK: - Trigger handling

    private func evaluateTrigger(_ trigger: PromoTrigger) async {
        let matchingPromos = promos.filter { $0.triggers.contains(trigger) }

        for promo in matchingPromos {
            let passesRules = checkRules(for: promo)
            guard passesRules else { continue }

            let record = historyStore.record(for: promo.id)
            guard !record.isPermanentlyDismissed, record.isEligible else { continue }

            guard promo.isEligible else { continue }

            performShow(promo: promo, record: record, isRestore: false)
            return
        }
    }

    // MARK: - Step 1: Rules

    private func checkRules(for promo: any Promo) -> Bool {
        if isExternalLaunch { return false }

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

        if severity >= .medium {
            if let last = lastInitiatedShow[promo.initiated] {
                let hours = promo.initiated.cooldownHours
                let interval = TimeInterval(hours * 3600)
                if Date().timeIntervalSince(last) < interval { return false }
            }

            if context == .newTabPage && !visibleIds.isDisjoint(with: nextStepsPromoIds) {
                return false
            }
        }

        return true
    }

    // MARK: - Perform show

    private func performShow(promo: any Promo, record: PromoHistoryRecord, isRestore: Bool = false) {
        let promoId = promo.id
        var recordToUse = record
        if !isRestore {
            recordToUse.lastPresented = Date()
            historyStore.save(recordToUse)
            lastInitiatedShow[promo.initiated] = Date()
        }

        let eligibilityCancellable = promo.isEligiblePublisher
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
            let result = await promo.show(history: recordToUse)
            await MainActor.run {
                self?.handleShowResult(promoId: promoId, result: result)
            }
        }

        var session = ActiveShowSession(
            promo: promo,
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
        recordResultAndCleanup(promoId: promoId, result: session.promo.promoType.timeoutResult)
    }

    private func handleEligibilityLost(promoId: String) {
        recordResultAndCleanup(promoId: promoId, result: .none)
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

        let promo = session.promo

        switch result {
        case .actioned, .ignored(cooldown: nil):
            var record = historyStore.record(for: promoId)
            record.timesPresented += 1
            record.nextEligibleDate = .distantFuture
            historyStore.save(record)
        case .ignored(cooldown: let interval?):
            var record = historyStore.record(for: promoId)
            record.timesPresented += 1
            record.nextEligibleDate = Date().addingTimeInterval(interval)
            historyStore.save(record)
        case .none:
            break
        }

        activeSessions.removeValue(forKey: promoId)
        visiblePromoIds.send(Set(activeSessions.keys))

        promo.hide()
    }

    private func updateHistoryForDismissedPromo(promoId: String, result: PromoResult) {
        var record = historyStore.record(for: promoId)
        switch result {
        case .actioned, .ignored(cooldown: nil):
            record.timesPresented += 1
            record.nextEligibleDate = .distantFuture
            historyStore.save(record)
        case .ignored(cooldown: let interval?):
            record.timesPresented += 1
            record.nextEligibleDate = Date().addingTimeInterval(interval)
            historyStore.save(record)
        case .none:
            break
        }
    }
}

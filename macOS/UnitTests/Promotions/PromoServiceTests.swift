//
//  PromoServiceTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class PromoServiceTests: XCTestCase {

    private var triggerSubject: PassthroughSubject<PromoTrigger, Never>!
    private var historyStore: MockPromoHistoryStore!
    private var testQueue: DispatchQueue!
    private var cancellables = Set<AnyCancellable>()
    private let timeout: TimeInterval = 5.0

    override func setUp() {
        super.setUp()
        triggerSubject = PassthroughSubject<PromoTrigger, Never>()
        historyStore = MockPromoHistoryStore()
        testQueue = DispatchQueue(label: "test.promoService")
    }

    override func tearDown() {
        triggerSubject = nil
        historyStore = nil
        testQueue = nil
        cancellables.removeAll()
        super.tearDown()
    }

    private func drainStateQueue() {
        let exp = XCTestExpectation(description: "stateQueue drained")
        testQueue.async { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    private func makeService(
        promos: [Promo],
        initialExternalActivation: Bool = false,
        evaluationDeferralWindow: TimeInterval = 0,
        registrationFallbackTimeout: TimeInterval = 0,
        externalActivationWindow: TimeInterval = 0
    ) -> PromoService {
        PromoService(
            promos: promos,
            historyStore: historyStore,
            triggerPublisher: triggerSubject.eraseToAnyPublisher(),
            initialExternalActivation: initialExternalActivation,
            stateQueue: testQueue,
            evaluationDeferralWindow: evaluationDeferralWindow,
            registrationFallbackTimeout: registrationFallbackTimeout,
            externalActivationWindow: externalActivationWindow
        )
    }

    // MARK: - Rule evaluation

    func testWhenOneMediumPromoVisible_ThenSecondMediumPromoIsSkipped() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "promo-1", delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "promo-2", delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "promo-2" }) {
                    XCTFail("Second promo should not be shown")
                } else if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        delegate1.completeShow(with: .actioned)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
        XCTAssertEqual(historyStore.saveCallCount, 1)
    }

    func testWhenTwoMediumPromosHaveMutualCoexistingIds_ThenBothCanBeVisible() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        let promo1 = PromoTestHelpers.makePromo(id: "coexist-a", coexistingPromoIDs: ["coexist-b"], delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "coexist-b", coexistingPromoIDs: ["coexist-a"], delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promos are hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        delegate1.completeShow(with: .actioned)
        delegate2.completeShow(with: .actioned)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 1)
    }

    func testWhenExternalActivationIsTrue_ThenAllPromosSuppressed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true, externalActivationWindow: 0.1)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
        XCTAssertEqual(historyStore.saveCallCount, 0)
    }

    func testWhenLowSeverityPromo_ThenSkipsAllRulesIncludingExternalActivation() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "low-promo", severity: .low, delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenGlobalPromoVisible_ThenOtherContextPromoBlocked() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        delegate1.setShowResult(.none)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "global", context: .global, delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "ntp", context: .newTabPage, delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.context == .newTabPage }) {
                    XCTFail("New tab page context should be blocked by global context promo")
                } else if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        triggerSubject.send(.newTabPageAppeared)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
    }

    func testWhenTwoSameContextPromosHaveMutualCoexistingIds_ThenBothCanBeVisible() async {
        // Given: two newTabPage promos with mutual coexistence
        let delegate1 = MockPromoDelegate(isEligible: true)
        let delegate2 = MockPromoDelegate(isEligible: true)
        let triggers: Set<PromoTrigger> = [.appLaunched, .newTabPageAppeared]
        let promo1 = PromoTestHelpers.makePromo(id: "ntp-a", triggers: triggers, context: .newTabPage, coexistingPromoIDs: ["ntp-b"], delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "ntp-b", triggers: triggers, context: .newTabPage, coexistingPromoIDs: ["ntp-a"], delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promos are hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        triggerSubject.send(.newTabPageAppeared)
        delegate1.completeShow(with: .actioned)
        delegate2.completeShow(with: .actioned)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 1)
    }

    func testWhenCoexistingPromoBVisible_ThenPromoCWithoutCoexistenceWithBIsBlocked() async {
        // Given: A coexists with B, B coexists with A. C does not coexist with B. B is visible.
        let delegateA = MockPromoDelegate(isEligible: true)
        let delegateB = MockPromoDelegate(isEligible: true)
        let delegateC = MockPromoDelegate(isEligible: true)
        let promoA = PromoTestHelpers.makePromo(id: "promo-a", coexistingPromoIDs: ["promo-b"], delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "promo-b", coexistingPromoIDs: ["promo-a"], delegate: delegateB)
        let promoC = PromoTestHelpers.makePromo(id: "promo-c", coexistingPromoIDs: [], delegate: delegateC)
        let promoService = makeService(promos: [promoA, promoB, promoC])
        let showBExpectation = XCTestExpectation(description: "B is shown")
        let hideExpectation = XCTestExpectation(description: "all hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.contains(where: { $0.id == "promo-b" }) && !promos.contains(where: { $0.id == "promo-c" }) {
                    showBExpectation.fulfill()
                }
                if promos.isEmpty {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: show A and B (they coexist), C is blocked when evaluated
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showBExpectation], timeout: timeout)
        delegateA.completeShow(with: .actioned)
        delegateB.completeShow(with: .actioned)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        // Then: C was never shown
        XCTAssertEqual(delegateC.hideCallCount, 0)
    }

    func testWhenAppInitiatedPromoDismissedRecently_ThenGlobalCooldownBlocksNextAppPromo() async {
        // Given: promo-1 was dismissed 1 hour ago, cooldown is 24h
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var record = PromoHistoryRecord(id: "cooldown-promo")
        record.lastDismissed = oneHourAgo
        record.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["cooldown-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "cooldown-promo", initiated: .app, delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then: promo was not shown (blocked by global cooldown)
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenTriggerDoesNotMatchPromoTriggers_ThenPromoNotEvaluated() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "ntp-only", triggers: [.newTabPageAppeared], delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.windowBecameKey)
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
        XCTAssertEqual(delegate.refreshEligibilityCallCount, 0)
    }

    func testWhenMultiplePromosMatchTrigger_ThenHighestPrioritySelected() async {
        // Given
        let delegate1 = MockPromoDelegate(isEligible: true)
        delegate1.setShowResult(.actioned)
        let delegate2 = MockPromoDelegate(isEligible: true)
        delegate2.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "high-priority", delegate: delegate1)
        let promo2 = PromoTestHelpers.makePromo(id: "low-priority", delegate: delegate2)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate1.hideCallCount, 1)
        XCTAssertEqual(delegate2.hideCallCount, 0)
    }

    func testWhenActionedResult_ThenPermanentlyDismissed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "actioned-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let record = historyStore.record(for: "actioned-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenIgnoredWithCooldown_ThenTemporaryCooldownSet() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: 86400))
        let promo = PromoTestHelpers.makePromo(id: "cooldown-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        let record = historyStore.record(for: "cooldown-promo")
        XCTAssertNotNil(record.nextEligibleDate)
        XCTAssertNotEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenIgnoredWithNilCooldown_ThenPermanentlyDismissed() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: nil))
        let promo = PromoTestHelpers.makePromo(id: "ignored-nil-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        let record = historyStore.record(for: "ignored-nil-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenNoneResult_ThenNoStateChange() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.none)
        let promo = PromoTestHelpers.makePromo(id: "none-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then
        let record = historyStore.record(for: "none-promo")
        XCTAssertEqual(record.timesDismissed, 0)
        XCTAssertNil(record.lastDismissed)
    }

    func testWhenDismissNonVisiblePromo_ThenHistoryUpdated() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "dismiss-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.dismiss(promoId: "dismiss-promo", result: .actioned)
        drainStateQueue()

        // Then
        let record = historyStore.record(for: "dismiss-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenUndismissWithClearHistory_ThenResetsTimesDismissed() async {
        // Given
        var record = PromoHistoryRecord(id: "undismiss-promo")
        record.timesDismissed = 2
        record.lastDismissed = Date()
        record.nextEligibleDate = .distantFuture
        historyStore = MockPromoHistoryStore(records: ["undismiss-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "undismiss-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.undismiss(promoId: "undismiss-promo", clearHistory: true)
        drainStateQueue()

        // Then
        let loaded = historyStore.record(for: "undismiss-promo")
        XCTAssertEqual(loaded.timesDismissed, 0)
        XCTAssertNil(loaded.lastDismissed)
        XCTAssertNil(loaded.nextEligibleDate)
    }

    func testWhenUndismissWithClearHistoryFalse_ThenPreservesTimesDismissed() async {
        // Given
        var record = PromoHistoryRecord(id: "undismiss-preserve-promo")
        record.timesDismissed = 3
        record.lastDismissed = Date()
        record.nextEligibleDate = .distantFuture
        historyStore = MockPromoHistoryStore(records: ["undismiss-preserve-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "undismiss-preserve-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        promoService.undismiss(promoId: "undismiss-preserve-promo", clearHistory: false)
        drainStateQueue()

        // Then: nextEligibleDate cleared but timesDismissed preserved
        let loaded = historyStore.record(for: "undismiss-preserve-promo")
        XCTAssertEqual(loaded.timesDismissed, 3)
        XCTAssertNotNil(loaded.lastDismissed)
        XCTAssertNil(loaded.nextEligibleDate)
    }

    // MARK: - Delegate readiness

    func testWhenAllDelegatesSetBeforeStart_ThenCompleteRegistrationFiresImmediately() async {
        // Given: all promos have delegates from init
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: promo was shown (registration completed immediately, trigger was processed)
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenNotAllDelegatesSet_ThenFallbackTimeoutCompletesRegistration() async {
        // Given: one promo without delegate
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promoWithDelegate = PromoTestHelpers.makePromo(id: "with-delegate", delegate: delegate)
        let promoWithoutDelegate = PromoTestHelpers.makePromo(id: "without-delegate", delegate: nil)
        let promoService = makeService(promos: [promoWithoutDelegate, promoWithDelegate], registrationFallbackTimeout: 0.05)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: trigger before fallback, then wait for fallback
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: promo with delegate was shown after fallback completed registration
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenDelegateSetAfterStart_ThenCompleteRegistrationRunsImmediately() async {
        // Given: one promo without delegate
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "late-delegate", delegate: nil)
        let promoService = makeService(promos: [promo], registrationFallbackTimeout: 1.0)
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        promoService.setDelegate(for: "late-delegate", delegate: delegate)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: registration completed via setDelegate, buffered trigger was processed
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenCompleteRegistrationCalledTwice_ThenIdempotent() async {
        // Given: all delegates set
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: applicationDidBecomeActive triggers registration; setDelegate again (no-op, already set)
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        promoService.setDelegate(for: "test-promo", delegate: delegate)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: only one show (no double processing)
        XCTAssertEqual(delegate.showCallCount, 1)
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenTriggersArriveBeforeRegistration_ThenBufferedAndProcessedAfter() async {
        // Given: trigger sent before applicationDidBecomeActive
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: trigger first, then activate (trigger gets buffered, processed when deferral runs)
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenExternallyActivatedAtRegistration_ThenBufferedTriggersDiscarded() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo], initialExternalActivation: true, externalActivationWindow: 1.0)
        let expectation = XCTestExpectation(description: "no promo shown")
        expectation.isInverted = true
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        triggerSubject.send(.appLaunched)
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then: promo was never shown (buffered triggers discarded due to external activation)
        await fulfillment(of: [expectation], timeout: 0.5)
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenPromoWithoutDelegate_ThenSkippedDuringEvaluation() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promoWithDelegate = PromoTestHelpers.makePromo(id: "with-delegate", delegate: delegate)
        let promoWithoutDelegate = PromoTestHelpers.makePromo(id: "without-delegate", delegate: nil)
        let promoService = makeService(promos: [promoWithoutDelegate, promoWithDelegate])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    // MARK: - Cooldown options

    func testWhenRespectsGlobalCooldownFalse_ThenCanShowDuringCooldown() async {
        // Given: other-promo dismissed 1h ago (sets cooldown). bypass-cooldown has respectsGlobalCooldown: false
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var otherRecord = PromoHistoryRecord(id: "other-promo")
        otherRecord.lastDismissed = oneHourAgo
        otherRecord.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["other-promo": otherRecord])
        let delegateOther = MockPromoDelegate(isEligible: true)
        delegateOther.setShowResult(.actioned)
        let delegateBypass = MockPromoDelegate(isEligible: true)
        delegateBypass.setShowResult(.actioned)
        let promo1 = PromoTestHelpers.makePromo(id: "other-promo", delegate: delegateOther)
        let promo2 = PromoTestHelpers.makePromo(id: "bypass-cooldown", respectsGlobalCooldown: false, delegate: delegateBypass)
        let promoService = makeService(promos: [promo1, promo2])
        let expectation = XCTestExpectation(description: "bypass promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: bypass-cooldown was shown despite global cooldown from other-promo
        XCTAssertEqual(delegateBypass.hideCallCount, 1)
        XCTAssertEqual(delegateOther.hideCallCount, 0)
    }

    func testWhenSetsGlobalCooldownFalse_ThenDismissalDoesNotContributeToCooldown() async {
        // Given: promo A has setsGlobalCooldown: false, promo B has default
        let delegateA = MockPromoDelegate(isEligible: true)
        delegateA.setShowResult(.actioned)
        let delegateB = MockPromoDelegate(isEligible: true)
        let promoA = PromoTestHelpers.makePromo(id: "no-cooldown-a", setsGlobalCooldown: false, delegate: delegateA)
        let promoB = PromoTestHelpers.makePromo(id: "cooldown-b", delegate: delegateB)
        let promoService = makeService(promos: [promoA, promoB])
        let hideExpectation = XCTestExpectation(description: "promo a hidden")
        let showExpectation = XCTestExpectation(description: "promo b shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    hideExpectation.fulfill()
                } else if promos.contains(where: { $0.id == "cooldown-b" }) {
                    showExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: show A, dismiss A, trigger again - B should show (A's dismiss didn't set cooldown)
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [hideExpectation], timeout: timeout)
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)

        // Then: B was shown (A's dismissal didn't block it)
        XCTAssertEqual(delegateB.showCallCount, 1)
    }

    func testWhenDefaultCooldownOptions_ThenStandardCooldownBehavior() async {
        // Given: default respectsGlobalCooldown and setsGlobalCooldown
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "default-cooldown", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: record has nextEligibleDate set (permanent dismiss)
        let record = historyStore.record(for: "default-cooldown")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
    }

    func testWhenRefreshEligibilityCalled_ThenDelegateRefreshEligibilityInvoked() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is shown")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertGreaterThan(delegate.refreshEligibilityCallCount, 0)
    }

    // MARK: - Timeout and eligibility

    func testWhenTimeoutFiresBeforeShowReturns_ThenTimeoutResultRecorded() async {
        // Given: promo with short timeout
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(
            id: "timeout-promo",
            timeoutInterval: 0.05,
            timeoutResult: .actioned,
            delegate: delegate
        )
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo hidden after timeout")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        let record = historyStore.record(for: "timeout-promo")
        XCTAssertEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenShowReturnsBeforeTimeout_ThenTimeoutCancelled() async {
        // Given: promo with long timeout, show returns quickly
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.ignored(cooldown: 3600))
        let promo = PromoTestHelpers.makePromo(
            id: "show-first-promo",
            timeoutInterval: 10,
            timeoutResult: .actioned,
            delegate: delegate
        )
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then: show result (.ignored) recorded, not timeout result
        let record = historyStore.record(for: "show-first-promo")
        XCTAssertNotEqual(record.nextEligibleDate, .distantFuture)
        XCTAssertEqual(record.timesDismissed, 1)
    }

    func testWhenEligibilityLostDuringShow_ThenHideCalledAndNoneRecorded() async {
        // Given: show suspends, we flip eligibility to false
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "eligibility-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let showExpectation = XCTestExpectation(description: "promo shown")
        let hideExpectation = XCTestExpectation(description: "promo hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if !promos.isEmpty {
                    showExpectation.fulfill()
                } else {
                    hideExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)
        delegate.setEligible(false)
        await fulfillment(of: [hideExpectation], timeout: timeout)

        let record = historyStore.record(for: "eligibility-promo")
        XCTAssertEqual(record.timesDismissed, 0)
        XCTAssertNil(record.lastDismissed)
    }

    func testWhenResetDebugState_ThenHistoryClearedAndHideCalled() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "reset-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let showExpectation = XCTestExpectation(description: "promo is shown")
        let hideExpectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    hideExpectation.fulfill()
                } else {
                    showExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [showExpectation], timeout: timeout)
        promoService.resetDebugState()
        await fulfillment(of: [hideExpectation], timeout: timeout)

        // Then
        XCTAssertEqual(historyStore.resetAllCallCount, 1)
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    func testWhenVisiblePromosPersisted_ThenRestoredOnNextLaunch() async {
        // Given
        historyStore.saveVisiblePromoIds(["restore-promo"])
        let record = PromoHistoryRecord(id: "restore-promo")
        historyStore.save(record)
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.none)
        let promo = PromoTestHelpers.makePromo(id: "restore-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertEqual(delegate.hideCallCount, 1)
    }

    // MARK: - Restore on restart

    func testWhenRestorePromoNotEligible_ThenSlotFreedWithoutResult() async {
        // Given
        historyStore.saveVisiblePromoIds(["ineligible-restore"])
        let record = PromoHistoryRecord(id: "ineligible-restore")
        historyStore.save(record)
        let delegate = MockPromoDelegate(isEligible: false)
        let promo = PromoTestHelpers.makePromo(id: "ineligible-restore", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    // MARK: - Debug and visiblePromosPublisher

    func testWhenDebugSimulatedDateSet_ThenUsedForCooldownAndEligibility() async {
        // Given: promo dismissed 2h ago, cooldown 24h. Simulate "now" as 1h after dismiss.
        let dismissTime = Date().addingTimeInterval(-7200)
        var record = PromoHistoryRecord(id: "debug-date-promo")
        record.lastDismissed = dismissTime
        record.timesDismissed = 1
        historyStore = MockPromoHistoryStore(records: ["debug-date-promo": record])
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "debug-date-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        promoService.setDebugSimulatedDate(dismissTime.addingTimeInterval(3600))

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        drainStateQueue()

        // Then
        XCTAssertEqual(delegate.hideCallCount, 0)
    }

    func testWhenVisiblePromosPublisher_ThenEmitsOnShowAndHide() async {
        // Given
        let delegate = MockPromoDelegate(isEligible: true)
        delegate.setShowResult(.actioned)
        let promo = PromoTestHelpers.makePromo(id: "publisher-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])
        var emissions: [[String]] = []
        let expectation = XCTestExpectation(description: "promo is hidden")
        promoService.visiblePromosPublisher
            .dropFirst()
            .sink { promos in
                emissions.append(promos.map { $0.id })
                if promos.isEmpty {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When
        promoService.applicationDidBecomeActive()
        triggerSubject.send(.appLaunched)
        await fulfillment(of: [expectation], timeout: timeout)

        // Then
        XCTAssertTrue(emissions.contains { $0 == ["publisher-promo"] })
        XCTAssertTrue(emissions.contains { $0.isEmpty })
    }

    func testWhenPersistedVisiblePromoIdNotInPromoList_ThenSkippedWithoutError() async {
        // Given: persisted ID for a promo that was removed from the app
        historyStore.saveVisiblePromoIds(["removed-promo"])
        let delegate = MockPromoDelegate(isEligible: true)
        let promo = PromoTestHelpers.makePromo(id: "current-promo", delegate: delegate)
        let promoService = makeService(promos: [promo])

        // When
        promoService.applicationDidBecomeActive()
        drainStateQueue()

        // Then: no crash, removed-promo is skipped
        XCTAssertEqual(delegate.hideCallCount, 0)
    }
}

//
//  NextStepsCardsPromo.swift
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
import NewTabPage

@MainActor
final class NextStepsCardsPromo: Promo {

    let id = "next-steps-cards"
    let triggers: Set<PromoTrigger> = [.newTabPageAppeared]
    let initiated: PromoInitiated = .app
    let promoType = PromoType(severity: .medium)
    let context: PromoContext = .newTabPage
    let coexistingPromoIDs: Set<String> = ["remote-message"]

    var isEligible: Bool {
        isPromoServiceEnabled() && !provider.cards.isEmpty
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        eligibilitySubject.eraseToAnyPublisher()
    }

    private let provider: NewTabPageNextStepsCardsProviding
    private let isPromoServiceEnabled: () -> Bool
    private let eligibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()
    private var showContinuation: CheckedContinuation<PromoResult, Never>?

    init(
        provider: NewTabPageNextStepsCardsProviding,
        isPromoServiceEnabled: @escaping () -> Bool = { false }
    ) {
        self.provider = provider
        self.isPromoServiceEnabled = isPromoServiceEnabled
        let initial = isPromoServiceEnabled() && !provider.cards.isEmpty
        self.eligibilitySubject = CurrentValueSubject(initial)

        provider.cardsPublisher
            .map { [weak self] cards in
                !cards.isEmpty && (self?.isPromoServiceEnabled() ?? false)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eligible in
                self?.eligibilitySubject.send(eligible)
            }
            .store(in: &cancellables)
    }

    /// Legacy code presents the cards. Suspend until PromoService calls hide() (via handleEligibilityLost
    /// when isEligiblePublisher emits false) or the show task is cancelled.
    func show(history: PromoHistoryRecord) async -> PromoResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                showContinuation = continuation
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.showContinuation?.resume(returning: .ignored())
                self?.showContinuation = nil
            }
        }
    }

    func hide() {
        showContinuation?.resume(returning: .ignored())
        showContinuation = nil
    }
}

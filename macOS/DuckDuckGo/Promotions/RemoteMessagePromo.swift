//
//  RemoteMessagePromo.swift
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
final class RemoteMessagePromo: Promo {

    let id = "remote-message"
    let triggers: Set<PromoTrigger> = [.newTabPageAppeared]
    let initiated: PromoInitiated = .app
    let promoType = PromoType(severity: .medium)
    let context: PromoContext = .newTabPage
    let coexistingPromoIDs: Set<String> = ["next-steps-cards"]

    var isEligible: Bool {
        isPromoServiceEnabled() && provider.newTabPageRemoteMessage != nil
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        eligibilitySubject.eraseToAnyPublisher()
    }

    private let provider: NewTabPageActiveRemoteMessageProviding
    private let isPromoServiceEnabled: () -> Bool
    private let eligibilitySubject: CurrentValueSubject<Bool, Never>
    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        provider: NewTabPageActiveRemoteMessageProviding,
        isPromoServiceEnabled: @escaping () -> Bool = { false }
    ) {
        self.provider = provider
        self.isPromoServiceEnabled = isPromoServiceEnabled
        let initial = isPromoServiceEnabled() && provider.newTabPageRemoteMessage != nil
        self.eligibilitySubject = CurrentValueSubject(initial)

        provider.newTabPageRemoteMessagePublisher
            .map { [weak self] message in
                (message != nil) && (self?.isPromoServiceEnabled() ?? false)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] eligible in
                self?.eligibilitySubject.send(eligible)
            }
            .store(in: &cancellables)
    }

    func show(history: PromoHistoryRecord) async -> PromoResult {
        await withCheckedContinuation { continuation in
            showContinuation = continuation
        }
    }

    func hide() {
        showContinuation?.resume(returning: .none)
        showContinuation = nil
    }
}

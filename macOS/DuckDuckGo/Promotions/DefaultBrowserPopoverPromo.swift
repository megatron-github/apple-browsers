//
//  DefaultBrowserPopoverPromo.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use it except in compliance with the License.
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

@MainActor
final class DefaultBrowserPopoverPromo: Promo {

    let id = "default-browser-popover"
    let triggers: Set<PromoTrigger> = [.windowBecameKey]
    let initiated: PromoInitiated = .app
    let promoType = PromoType(severity: .medium)
    let context: PromoContext = .global

    var isEligible: Bool {
        isPromoServiceEnabled() && coordinator.popoverEligibility.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        coordinator.popoverEligibility
            .map { [weak self] eligible in eligible && (self?.isPromoServiceEnabled() ?? false) }
            .eraseToAnyPublisher()
    }

    private let coordinator: DefaultBrowserAndDockPromptCoordinator
    private let presenter: DefaultBrowserAndDockPromptPresenting
    private let uiProvidersProvider: () -> DefaultBrowserPromptUIProvidersProviding?
    private let isPromoServiceEnabled: () -> Bool
    private var showContinuation: CheckedContinuation<PromoResult, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(
        coordinator: DefaultBrowserAndDockPromptCoordinator,
        presenter: DefaultBrowserAndDockPromptPresenting,
        uiProvidersProvider: @escaping () -> DefaultBrowserPromptUIProvidersProviding?,
        isPromoServiceEnabled: @escaping () -> Bool = { false }
    ) {
        self.coordinator = coordinator
        self.presenter = presenter
        self.uiProvidersProvider = uiProvidersProvider
        self.isPromoServiceEnabled = isPromoServiceEnabled
    }

    convenience init(service: DefaultBrowserAndDockPromptService,
                     isPromoServiceEnabled: @escaping () -> Bool = { false }) {
        self.init(coordinator: service.coordinator,
                  presenter: service.presenter,
                  uiProvidersProvider: service.uiProvidersProvider,
                  isPromoServiceEnabled: isPromoServiceEnabled)
    }

    func show(history: PromoHistoryRecord) async -> PromoResult {
        guard coordinator.promptTypeForEligibilityCheck() == .active(.popover) else {
            return .none
        }
        guard let provider = uiProvidersProvider() else {
            return .none
        }

        return await withCheckedContinuation { continuation in
            showContinuation = continuation

            let prov = provider
            presenter.tryToShowPrompt(
                popoverAnchorProvider: { prov.providePopoverAnchor() },
                bannerViewHandler: { prov.showBanner($0) },
                inactiveUserModalWindowProvider: { prov.provideInactiveUserModalWindow() }
            )

            presenter.promptDismissedPublisher
                .first()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.showContinuation?.resume(returning: .none)
                    self?.showContinuation = nil
                }
                .store(in: &cancellables)
        }
    }

    func hide() {
        showContinuation?.resume(returning: .none)
        showContinuation = nil
    }

    func refreshEligibility() {
        coordinator.evaluateEligibility()
    }
}

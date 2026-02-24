//
//  PromoServiceFactory.swift
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

import AppKit
import Combine
import Persistence

struct PromoServiceFactory {
    /// Promotions to be coordinated by `PromoService`.
    static let promos: [Promo] = []

    /// Triggers for promotions, mapped to `PromoTrigger` values.
    static let triggerPublisher = Publishers.Merge3(
        NotificationCenter.default.publisher(for: .promoServiceAppLaunched)
            .map { _ in PromoTrigger.appLaunched },
        NotificationCenter.default.publisher(for: .newTabPageWebViewDidAppear)
            .map { _ in PromoTrigger.newTabPageAppeared },
        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .map { _ in PromoTrigger.windowBecameKey }
    ).eraseToAnyPublisher()

    @MainActor
    static func makePromoService(keyValueStore: ThrowingKeyValueStoring,
                                 isExternallyActivated: Bool) -> PromoService {
        let stateQueue = DispatchQueue(label: "com.duckduckgo.promoService.state")
        let historyStore = PromoHistoryStore(store: keyValueStore, queue: stateQueue)
        return PromoService(
            promos: promos,
            historyStore: historyStore,
            triggerPublisher: triggerPublisher,
            initialExternalActivation: isExternallyActivated,
            stateQueue: stateQueue
        )
    }
}

extension Notification.Name {
    static let promoServiceAppLaunched = Notification.Name("com.duckduckgo.app.promoService.appLaunched")
}

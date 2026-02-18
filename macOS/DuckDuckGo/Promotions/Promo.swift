//
//  Promo.swift
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

protocol Promo: AnyObject {
    /// Unique identifier, e.g. "set-as-default-banner"
    var id: String { get }

    /// Which trigger(s) this promo responds to
    var triggers: Set<PromoTrigger> { get }

    /// How this promo was initiated and its cooldown
    var initiated: PromoInitiated { get }

    /// Display metadata (severity, timeout)
    var promoType: PromoType { get }

    /// Where this promo appears
    var context: PromoContext { get }

    /// IDs of promos that can be visible simultaneously with this one.
    /// Promos can appear together when all visible promos that would conflict
    /// are in this set and this promo is in all of theirs (mutual coexistence).
    /// This should be used only in very rare cases that are pre-validated (e.g. with a PFR).
    /// Default: empty (no coexistence exceptions).
    var coexistingPromoIDs: Set<String> { get }

    /// Current eligibility state. Use isEligiblePublisher to observe changes.
    var isEligible: Bool { get }

    /// Publisher indicating whether this promo is currently eligible.
    /// Must emit a current value immediately on subscription (use CurrentValueSubject).
    var isEligiblePublisher: AnyPublisher<Bool, Never> { get }

    /// Shows the promo. Returns when user interacts, promo retracts, or hide() is called.
    /// Receives the promo's own history for result decisions (e.g. varying cooldown by timesPresented).
    @MainActor
    func show(history: PromoHistoryRecord) async -> PromoResult

    /// Hides the promo. Must be idempotent.
    /// PromoService calls hide() after recording any result, so a promo that has
    /// already hidden its own UI will receive a second hide() that should be a no-op.
    @MainActor
    func hide()
}

extension Promo {
    var coexistingPromoIDs: Set<String> { [] }
}

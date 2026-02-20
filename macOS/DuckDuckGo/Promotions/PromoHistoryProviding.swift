//
//  PromoHistoryProviding.swift
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

protocol PromoHistoryProviding {
    /// Publisher for a single promo's history. Emits nil if no history exists.
    func historyPublisher(for promoId: String) -> AnyPublisher<PromoHistoryRecord?, Never>

    /// Publisher for all history records.
    var allHistoryPublisher: AnyPublisher<[PromoHistoryRecord], Never> { get }
}

protocol PromoHistoryStoring: PromoHistoryProviding {
    func record(for promoId: String) -> PromoHistoryRecord
    func save(_ record: PromoHistoryRecord)
    func allRecords() -> [PromoHistoryRecord]

    /// Persists visible promo IDs for restore-on-restart.
    func saveVisiblePromoIds(_ ids: Set<String>)

    /// Loads persisted visible promo IDs. Returns empty set on failure.
    func loadVisiblePromoIds() -> Set<String>

    /// Clears all history records and persisted visible promo IDs. For debug reset.
    func resetAll()
}

//
//  PromoHistoryStore.swift
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
import Common
import Foundation
import os.log
import Persistence

final class PromoHistoryStore: PromoHistoryStoring {

    private static let storageKey = "com.duckduckgo.promo.history"
    private static let visibleIdsStorageKey = "com.duckduckgo.promo.visibleIds"

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let store: ThrowingKeyValueStoring
    private var records: [String: PromoHistoryRecord]
    private let recordsSubject: CurrentValueSubject<[String: PromoHistoryRecord], Never>

    init(store: ThrowingKeyValueStoring) {
        self.store = store
        let loaded = Self.load(from: store)
        self.records = loaded
        self.recordsSubject = CurrentValueSubject(loaded)
    }

    func record(for promoId: String) -> PromoHistoryRecord {
        records[promoId] ?? PromoHistoryRecord(id: promoId)
    }

    func save(_ record: PromoHistoryRecord) {
        records[record.id] = record
        persist()
        recordsSubject.send(records)
    }

    func allRecords() -> [PromoHistoryRecord] {
        Array(records.values)
    }

    func historyPublisher(for promoId: String) -> AnyPublisher<PromoHistoryRecord?, Never> {
        recordsSubject
            .map { $0[promoId] }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    var allHistoryPublisher: AnyPublisher<[PromoHistoryRecord], Never> {
        recordsSubject
            .map { Array($0.values) }
            .eraseToAnyPublisher()
    }

    func saveVisiblePromoIds(_ ids: Set<String>) {
        do {
            let data = try Self.encoder.encode(Array(ids))
            try store.set(data, forKey: Self.visibleIdsStorageKey)
        } catch {
            Logger.general.error("PromoHistoryStore failed to persist visible promo IDs: \(error.localizedDescription)")
        }
    }

    func loadVisiblePromoIds() -> Set<String> {
        do {
            guard let data = try store.object(forKey: Self.visibleIdsStorageKey) as? Data else { return [] }
            let array = try Self.decoder.decode([String].self, from: data)
            return Set(array)
        } catch {
            Logger.general.error("PromoHistoryStore failed to load visible promo IDs: \(error.localizedDescription)")
            return []
        }
    }

    func resetAll() {
        records = [:]
        persist()
        saveVisiblePromoIds([])
        recordsSubject.send(records)
    }

    private func persist() {
        do {
            let data = try Self.encoder.encode(records)
            try store.set(data, forKey: Self.storageKey)
        } catch {
            Logger.general.error("PromoHistoryStore failed to persist: \(error.localizedDescription)")
        }
    }

    private static func load(from store: ThrowingKeyValueStoring) -> [String: PromoHistoryRecord] {
        do {
            guard let data = try store.object(forKey: storageKey) as? Data else { return [:] }
            return try decoder.decode([String: PromoHistoryRecord].self, from: data)
        } catch {
            Logger.general.error("PromoHistoryStore failed to load: \(error.localizedDescription)")
            return [:]
        }
    }
}

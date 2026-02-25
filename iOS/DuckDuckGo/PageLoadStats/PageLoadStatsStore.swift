//
//  PageLoadStatsStore.swift
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

import Foundation

protocol PageLoadStatsStoring {
    func recordEntry(_ entry: PageLoadStatEntry)
    func fetchAllStats() -> [PageLoadStatEntry]
    func clearAllStats()
}

final class PageLoadStatsStore: PageLoadStatsStoring {

    static let shared = PageLoadStatsStore()

    private enum Constants {
        static let storageKey = "com.duckduckgo.pageload.stats"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func recordEntry(_ entry: PageLoadStatEntry) {
        var stats = fetchAllStats()
        stats.append(entry)
        saveStats(stats)
    }

    func fetchAllStats() -> [PageLoadStatEntry] {
        guard let data = userDefaults.data(forKey: Constants.storageKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([PageLoadStatEntry].self, from: data)
        } catch {
            return []
        }
    }

    func clearAllStats() {
        userDefaults.removeObject(forKey: Constants.storageKey)
    }

    private func saveStats(_ stats: [PageLoadStatEntry]) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(stats)
            userDefaults.set(data, forKey: Constants.storageKey)
        } catch {
            assertionFailure("Failed to encode page load stats: \(error)")
        }
    }
}

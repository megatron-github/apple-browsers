//
//  AutoconsentStatsDebugViewModel.swift
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
import Combine

struct AutoconsentHostStatsSummary: Identifiable {
    let host: String
    let entryCount: Int
    let averageDuration: TimeInterval

    var id: String { host }
}

final class AutoconsentStatsDebugViewModel: ObservableObject {

    @Published var stats: [AutoconsentPerURLStatEntry] = []

    var groupedByHost: [AutoconsentHostStatsSummary] {
        let grouped = Dictionary(grouping: stats) { $0.host }
        return grouped.map { host, entries in
            let totalDuration = entries.reduce(0) { $0 + $1.duration }
            let averageDuration = entries.isEmpty ? 0 : totalDuration / Double(entries.count)
            return AutoconsentHostStatsSummary(
                host: host,
                entryCount: entries.count,
                averageDuration: averageDuration
            )
        }.sorted { $0.entryCount > $1.entryCount }
    }

    private let store: AutoconsentPerURLStatsStoring

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(store: AutoconsentPerURLStatsStoring = AutoconsentPerURLStatsStore.shared) {
        self.store = store
        loadStats()
    }

    func loadStats() {
        stats = store.fetchAllStats().sorted { $0.timestamp > $1.timestamp }
    }

    func clearStats() {
        store.clearAllStats()
        stats = []
    }

    func exportToCSV() -> String {
        let header = "\"timestamp\",\"url\",\"host\",\"cmpName\",\"isCosmetic\",\"clicks\",\"durationMs\",\"fromExtension\""
        let rows = stats.map { entry -> String in
            let timestamp = Self.dateFormatter.string(from: entry.timestamp)
            let url = entry.url.absoluteString.escapedForCSV()
            let host = entry.host.escapedForCSV()
            let cmpName = entry.cmpName.escapedForCSV()
            let isCosmetic = entry.isCosmetic ? "true" : "false"
            let clicks = String(entry.totalClicks)
            let duration = String(format: "%.0f", entry.duration)
            let fromExtension = entry.fromExtension ? "true" : "false"
            return "\"\(timestamp)\",\"\(url)\",\"\(host)\",\"\(cmpName)\",\"\(isCosmetic)\",\"\(clicks)\",\"\(duration)\",\"\(fromExtension)\""
        }
        return ([header] + rows).joined(separator: "\n")
    }
}

private extension String {
    func escapedForCSV() -> String {
        return self.replacingOccurrences(of: "\"", with: "\"\"")
    }
}

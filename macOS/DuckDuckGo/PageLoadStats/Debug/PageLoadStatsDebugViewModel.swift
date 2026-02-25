//
//  PageLoadStatsDebugViewModel.swift
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

struct PageLoadHostStatsSummary: Identifiable {
    let host: String
    let entryCount: Int
    let averageLoadDuration: TimeInterval
    let averageTTFB: TimeInterval?
    let cpmEnabledCount: Int
    let cpmDisabledCount: Int

    var id: String { host }
}

@available(macOS 13.5, *)
final class PageLoadStatsDebugViewModel: ObservableObject {

    @Published var stats: [PageLoadStatEntry] = []

    var groupedByHost: [PageLoadHostStatsSummary] {
        let grouped = Dictionary(grouping: stats) { $0.host }
        return grouped.map { host, entries in
            let totalLoadDuration = entries.reduce(0) { $0 + $1.loadDuration }
            let averageLoadDuration = entries.isEmpty ? 0 : totalLoadDuration / Double(entries.count)

            let ttfbEntries = entries.compactMap { $0.ttfb }
            let averageTTFB: TimeInterval? = ttfbEntries.isEmpty ? nil : ttfbEntries.reduce(0, +) / Double(ttfbEntries.count)

            let cpmEnabled = entries.filter { $0.webExtensionCPMEnabled }.count
            let cpmDisabled = entries.count - cpmEnabled

            return PageLoadHostStatsSummary(
                host: host,
                entryCount: entries.count,
                averageLoadDuration: averageLoadDuration,
                averageTTFB: averageTTFB,
                cpmEnabledCount: cpmEnabled,
                cpmDisabledCount: cpmDisabled
            )
        }.sorted { $0.entryCount > $1.entryCount }
    }

    private let store: PageLoadStatsStoring

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(store: PageLoadStatsStoring = PageLoadStatsStore.shared) {
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
        let header = "\"timestamp\",\"url\",\"host\",\"loadDurationMs\",\"domCompleteMs\",\"domContentLoadedMs\",\"ttfbMs\",\"fcpMs\",\"webExtensionCPMEnabled\""
        let rows = stats.map { entry -> String in
            let timestamp = Self.dateFormatter.string(from: entry.timestamp)
            let url = entry.url.absoluteString.escapedForCSV()
            let host = entry.host.escapedForCSV()
            let loadDuration = String(format: "%.0f", entry.loadDuration)
            let domComplete = entry.domComplete.map { String(format: "%.0f", $0) } ?? ""
            let domContentLoaded = entry.domContentLoaded.map { String(format: "%.0f", $0) } ?? ""
            let ttfb = entry.ttfb.map { String(format: "%.0f", $0) } ?? ""
            let fcp = entry.firstContentfulPaint.map { String(format: "%.0f", $0) } ?? ""
            let cpmEnabled = entry.webExtensionCPMEnabled ? "true" : "false"
            return "\"\(timestamp)\",\"\(url)\",\"\(host)\",\"\(loadDuration)\",\"\(domComplete)\",\"\(domContentLoaded)\",\"\(ttfb)\",\"\(fcp)\",\"\(cpmEnabled)\""
        }
        return ([header] + rows).joined(separator: "\n")
    }
}

private extension String {
    func escapedForCSV() -> String {
        return self.replacingOccurrences(of: "\"", with: "\"\"")
    }
}

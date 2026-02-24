//
//  AutoconsentStatsDebugView.swift
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
import SwiftUI

@available(macOS 13.5, *)
struct AutoconsentStatsDebugView: View {

    enum ViewMode: String, CaseIterable {
        case detailed = "Detailed"
        case grouped = "Grouped by Host"
    }

    @StateObject private var viewModel: AutoconsentStatsDebugViewModel
    @State private var viewMode: ViewMode = .detailed
    @State private var sortOrder = [KeyPathComparator(\AutoconsentPerURLStatEntry.timestamp, order: .reverse)]
    @State private var groupedSortOrder = [KeyPathComparator(\AutoconsentHostStatsSummary.entryCount, order: .reverse)]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    init(store: AutoconsentPerURLStatsStoring = AutoconsentPerURLStatsStore()) {
        _viewModel = StateObject(wrappedValue: AutoconsentStatsDebugViewModel(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if viewMode == .detailed {
                detailedTableView
            } else {
                groupedTableView
            }
            statusBar
        }
        .frame(minWidth: 900, minHeight: 400)
    }

    private var toolbar: some View {
        HStack {
            Button("Refresh") {
                viewModel.loadStats()
            }

            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Spacer()
            Button("Export CSV...") {
                exportToCSV()
            }
            Button("Clear All") {
                clearAllStats()
            }
            .foregroundColor(.red)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var detailedTableView: some View {
        Table(viewModel.stats, sortOrder: $sortOrder) {
            TableColumn("Timestamp", value: \.timestamp) { entry in
                Text(Self.dateFormatter.string(from: entry.timestamp))
                    .textSelection(.enabled)
            }
            .width(min: 140, ideal: 160)

            TableColumn("Host", value: \.host) { entry in
                Text(entry.host)
                    .textSelection(.enabled)
            }
            .width(min: 120, ideal: 180)

            TableColumn("URL", value: \.url.absoluteString) { entry in
                Text(entry.url.absoluteString)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .width(min: 200, ideal: 300)

            TableColumn("CMP", value: \.cmpName) { entry in
                Text(entry.cmpName)
                    .textSelection(.enabled)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Cosmetic") { entry in
                Text(entry.isCosmetic ? "Yes" : "No")
            }
            .width(60)

            TableColumn("Clicks") { entry in
                Text("\(entry.totalClicks)")
            }
            .width(50)

            TableColumn("Duration (ms)") { entry in
                Text(String(format: "%.0f", entry.duration))
            }
            .width(80)

            TableColumn("Source") { entry in
                Text(entry.fromExtension ? "Extension" : "UserScript")
            }
            .width(80)
        }
        .onChange(of: sortOrder) { newOrder in
            viewModel.stats.sort(using: newOrder)
        }
    }

    private var groupedTableView: some View {
        Table(viewModel.groupedByHost, sortOrder: $groupedSortOrder) {
            TableColumn("Host", value: \.host) { summary in
                Text(summary.host)
                    .textSelection(.enabled)
            }
            .width(min: 200, ideal: 300)

            TableColumn("Count", value: \.entryCount) { summary in
                Text("\(summary.entryCount)")
            }
            .width(min: 60, ideal: 80)

            TableColumn("Avg Duration (ms)", value: \.averageDuration) { summary in
                Text(String(format: "%.0f", summary.averageDuration))
            }
            .width(min: 100, ideal: 140)
        }
    }

    private var statusBar: some View {
        HStack {
            if viewMode == .detailed {
                Text("\(viewModel.stats.count) entries")
                    .foregroundColor(.secondary)
            } else {
                Text("\(viewModel.groupedByHost.count) hosts")
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !viewModel.stats.isEmpty {
                let totalDuration = viewModel.stats.reduce(0) { $0 + $1.duration }
                Text("Total duration: \(formattedDuration(totalDuration))")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func formattedDuration(_ ms: TimeInterval) -> String {
        let seconds = ms / 1000
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds) / 60
            let remainingSeconds = Int(seconds) % 60
            return "\(minutes)m \(remainingSeconds)s"
        } else {
            let hours = Int(seconds) / 3600
            let minutes = (Int(seconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    private func exportToCSV() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Autoconsent Stats"
        savePanel.nameFieldStringValue = "autoconsent_stats.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]

        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                let csvContent = viewModel.exportToCSV()
                do {
                    try csvContent.write(to: url, atomically: true, encoding: .utf8)
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                } catch {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Could not save the CSV file: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func clearAllStats() {
        let alert = NSAlert()
        alert.messageText = "Clear All Stats?"
        alert.informativeText = "This will permanently delete all recorded autoconsent statistics. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearStats()
        }
    }
}

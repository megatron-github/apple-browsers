//
//  PageLoadStatsDebugView.swift
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
struct PageLoadStatsDebugView: View {

    enum ViewMode: String, CaseIterable {
        case detailed = "Detailed"
        case grouped = "Grouped by Host"
    }

    @StateObject private var viewModel: PageLoadStatsDebugViewModel
    @State private var viewMode: ViewMode = .detailed
    @State private var sortOrder = [KeyPathComparator(\PageLoadStatEntry.timestamp, order: .reverse)]
    @State private var groupedSortOrder = [KeyPathComparator(\PageLoadHostStatsSummary.entryCount, order: .reverse)]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    init(store: PageLoadStatsStoring = PageLoadStatsStore.shared) {
        _viewModel = StateObject(wrappedValue: PageLoadStatsDebugViewModel(store: store))
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
        .frame(minWidth: 1000, minHeight: 400)
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

            TableColumn("Load (ms)", value: \.loadDuration) { entry in
                Text(String(format: "%.0f", entry.loadDuration))
            }
            .width(70)

            TableColumn("TTFB") { entry in
                Text(entry.ttfb.map { String(format: "%.0f", $0) } ?? "-")
            }
            .width(60)

            TableColumn("FCP") { entry in
                Text(entry.firstContentfulPaint.map { String(format: "%.0f", $0) } ?? "-")
            }
            .width(60)

            TableColumn("DOM Complete") { entry in
                Text(entry.domComplete.map { String(format: "%.0f", $0) } ?? "-")
            }
            .width(90)

            TableColumn("CPM") { entry in
                Text(entry.webExtensionCPMEnabled ? "On" : "Off")
                    .foregroundColor(entry.webExtensionCPMEnabled ? .blue : .secondary)
            }
            .width(50)
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

            TableColumn("Avg Load (ms)", value: \.averageLoadDuration) { summary in
                Text(String(format: "%.0f", summary.averageLoadDuration))
            }
            .width(min: 90, ideal: 120)

            TableColumn("Avg TTFB") { summary in
                Text(summary.averageTTFB.map { String(format: "%.0f", $0) } ?? "-")
            }
            .width(min: 70, ideal: 90)

            TableColumn("CPM On", value: \.cpmEnabledCount) { summary in
                Text("\(summary.cpmEnabledCount)")
            }
            .width(min: 60, ideal: 80)

            TableColumn("CPM Off", value: \.cpmDisabledCount) { summary in
                Text("\(summary.cpmDisabledCount)")
            }
            .width(min: 60, ideal: 80)
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
                let avgLoadTime = viewModel.stats.reduce(0) { $0 + $1.loadDuration } / Double(viewModel.stats.count)
                Text(String(format: "Avg load: %.0f ms", avgLoadTime))
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func exportToCSV() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Page Load Stats"
        savePanel.nameFieldStringValue = "page_load_stats.csv"
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
        alert.informativeText = "This will permanently delete all recorded page load statistics. This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            viewModel.clearStats()
        }
    }
}

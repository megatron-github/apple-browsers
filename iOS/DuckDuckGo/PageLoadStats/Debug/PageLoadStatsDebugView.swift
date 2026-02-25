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

import SwiftUI

struct PageLoadStatsDebugView: View {

    enum ViewMode: String, CaseIterable {
        case detailed = "Detailed"
        case grouped = "Grouped"
    }

    @StateObject private var viewModel: PageLoadStatsDebugViewModel
    @State private var viewMode: ViewMode = .detailed
    @State private var showingClearConfirmation = false
    @State private var showingExportSheet = false

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
            Picker("View Mode", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            if viewMode == .detailed {
                detailedListView
            } else {
                groupedListView
            }

            statusBar
        }
        .navigationTitle("Page Load Stats")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    viewModel.loadStats()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }

                Button {
                    showingExportSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }

                Button {
                    showingClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("Clear All Stats?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                viewModel.clearStats()
            }
        } message: {
            Text("This will permanently delete all recorded page load statistics. This action cannot be undone.")
        }
        .sheet(isPresented: $showingExportSheet) {
            exportSheet
        }
    }

    private var detailedListView: some View {
        List(viewModel.stats) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.host)
                    .font(.headline)
                Text(entry.url.absoluteString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack {
                    Text(String(format: "Load: %.0f ms", entry.loadDuration))
                        .font(.caption)
                    Spacer()
                    Text(entry.webExtensionCPMEnabled ? "CPM On" : "CPM Off")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(entry.webExtensionCPMEnabled ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(4)
                }
                HStack(spacing: 8) {
                    if let ttfb = entry.ttfb {
                        Text(String(format: "TTFB: %.0f", ttfb))
                    }
                    if let fcp = entry.firstContentfulPaint {
                        Text(String(format: "FCP: %.0f", fcp))
                    }
                    if let domComplete = entry.domComplete {
                        Text(String(format: "DOM: %.0f", domComplete))
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                Text(Self.dateFormatter.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }

    private var groupedListView: some View {
        List(viewModel.groupedByHost) { summary in
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.host)
                        .font(.headline)
                    Text("\(summary.entryCount) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("CPM On: \(summary.cpmEnabledCount)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        Text("Off: \(summary.cpmDisabledCount)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "Avg: %.0f ms", summary.averageLoadDuration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let ttfb = summary.averageTTFB {
                        Text(String(format: "TTFB: %.0f", ttfb))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
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
                Text(String(format: "Avg: %.0f ms", avgLoadTime))
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var exportSheet: some View {
        PageLoadExportActivityViewController(activityItems: [viewModel.exportToCSV()])
    }
}

struct PageLoadExportActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

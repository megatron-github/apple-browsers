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

import SwiftUI

struct AutoconsentStatsDebugView: View {

    enum ViewMode: String, CaseIterable {
        case detailed = "Detailed"
        case grouped = "Grouped"
    }

    @StateObject private var viewModel: AutoconsentStatsDebugViewModel
    @State private var viewMode: ViewMode = .detailed
    @State private var showingClearConfirmation = false
    @State private var showingExportSheet = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    init(store: AutoconsentPerURLStatsStoring = AutoconsentPerURLStatsStore.shared) {
        _viewModel = StateObject(wrappedValue: AutoconsentStatsDebugViewModel(store: store))
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
        .navigationTitle("CPM Per-URL Stats")
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
            Text("This will permanently delete all recorded per-URL autoconsent statistics. This action cannot be undone.")
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
                    Label(entry.cmpName, systemImage: "shield")
                    Spacer()
                    Text(entry.fromExtension ? "Extension" : "UserScript")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(entry.fromExtension ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(4)
                    if entry.isCosmetic {
                        Text("Cosmetic")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .font(.caption)
                HStack {
                    Text(Self.dateFormatter.string(from: entry.timestamp))
                    Spacer()
                    Text("Clicks: \(entry.totalClicks)")
                    Text("•")
                    Text(String(format: "%.0f ms", entry.duration))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.plain)
    }

    private var groupedListView: some View {
        List(viewModel.groupedByHost) { summary in
            VStack(alignment: .leading, spacing: 6) {
                Text(summary.host)
                    .font(.headline)

                HStack(spacing: 12) {
                    if summary.extensionCount > 0 {
                        HStack(spacing: 4) {
                            Text("Extension")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                            Text("\(summary.extensionCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f ms", summary.extensionAverageDuration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if summary.userScriptCount > 0 {
                        HStack(spacing: 4) {
                            Text("UserScript")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(4)
                            Text("\(summary.userScriptCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.0f ms", summary.userScriptAverageDuration))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Text("\(summary.entryCount) total • Avg: \(String(format: "%.0f ms", summary.averageDuration))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                let totalDuration = viewModel.stats.reduce(0) { $0 + $1.duration }
                Text("Total: \(formattedDuration(totalDuration))")
                    .foregroundColor(.secondary)
            }
        }
        .font(.caption)
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }

    private var exportSheet: some View {
        ExportActivityViewController(activityItems: [viewModel.exportToCSV()])
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
}

struct ExportActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

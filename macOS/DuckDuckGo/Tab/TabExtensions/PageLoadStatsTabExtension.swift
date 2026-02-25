//
//  PageLoadStatsTabExtension.swift
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

import Combine
import Foundation
import Navigation
import WebKit
import WebExtensions
import os.log

extension Logger {
    static let pageLoadStats = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.duckduckgo", category: "PageLoadStats")
}

struct PageLoadJSMetrics {
    let loadComplete: TimeInterval
    let domComplete: TimeInterval
    let domContentLoaded: TimeInterval
    let ttfb: TimeInterval
    let firstContentfulPaint: TimeInterval?
}

final class PageLoadStatsTabExtension {

    private var navigationStartTime: Date?
    private let store: PageLoadStatsStoring
    private let webExtensionAvailabilityProvider: () -> Bool
    private weak var webView: WKWebView?

    private static let metricsScript = """
    (function() {
        const nav = performance.getEntriesByType('navigation')[0];
        const paint = performance.getEntriesByType('paint');
        const fcp = paint.find(p => p.name === 'first-contentful-paint');
        if (!nav) return null;
        return {
            loadComplete: nav.loadEventEnd - nav.fetchStart,
            domComplete: nav.domComplete - nav.fetchStart,
            domContentLoaded: nav.domContentLoadedEventEnd - nav.fetchStart,
            ttfb: nav.responseStart - nav.fetchStart,
            fcp: fcp ? fcp.startTime : null
        };
    })()
    """

    init(
        webViewPublisher: some Publisher<WKWebView, Never>,
        store: PageLoadStatsStoring = PageLoadStatsStore.shared,
        webExtensionAvailabilityProvider: @escaping () -> Bool
    ) {
        self.store = store
        self.webExtensionAvailabilityProvider = webExtensionAvailabilityProvider

        webViewPublisher.sink { [weak self] webView in
            self?.webView = webView
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func reset() {
        navigationStartTime = nil
    }

    @MainActor
    private func collectAndRecordMetrics(url: URL) async {
        guard let webView = webView,
              let startTime = navigationStartTime,
              url.scheme == "https" || url.scheme == "http" else {
            reset()
            return
        }

        let loadDuration = Date().timeIntervalSince(startTime) * 1000
        let jsMetrics = await collectJSMetrics(webView: webView)

        let entry = PageLoadStatEntry(
            url: url,
            host: url.host ?? "unknown",
            loadDuration: loadDuration,
            domComplete: jsMetrics?.domComplete,
            domContentLoaded: jsMetrics?.domContentLoaded,
            ttfb: jsMetrics?.ttfb,
            firstContentfulPaint: jsMetrics?.firstContentfulPaint,
            webExtensionCPMEnabled: webExtensionAvailabilityProvider()
        )

        store.recordEntry(entry)
        Logger.pageLoadStats.debug("Recorded entry for \(url.host ?? "unknown") - \(loadDuration)ms")
        reset()
    }

    @MainActor
    private func collectJSMetrics(webView: WKWebView) async -> PageLoadJSMetrics? {
        if #available(macOS 12.0, *) {
            do {
                let result = try await webView.evaluateJavaScript(Self.metricsScript, in: nil, contentWorld: .page)

                guard let metrics = result as? [String: Any] else {
                    return nil
                }

                guard let loadComplete = metrics["loadComplete"] as? Double,
                      let domComplete = metrics["domComplete"] as? Double,
                      let domContentLoaded = metrics["domContentLoaded"] as? Double,
                      let ttfb = metrics["ttfb"] as? Double else {
                    return nil
                }

                let fcp = metrics["fcp"] as? Double

                return PageLoadJSMetrics(
                    loadComplete: loadComplete,
                    domComplete: domComplete,
                    domContentLoaded: domContentLoaded,
                    ttfb: ttfb,
                    firstContentfulPaint: fcp
                )
            } catch {
                Logger.pageLoadStats.debug("Failed to collect JS metrics - \(error.localizedDescription)")
                return nil
            }
        } else {
            return nil
        }
    }
}

protocol PageLoadStatsTabExtensionProtocol: AnyObject, NavigationResponder {}

extension PageLoadStatsTabExtension: TabExtension, PageLoadStatsTabExtensionProtocol {
    func getPublicProtocol() -> PageLoadStatsTabExtensionProtocol { self }
}

extension TabExtensions {
    var pageLoadStats: PageLoadStatsTabExtensionProtocol? {
        resolve(PageLoadStatsTabExtension.self)
    }
}

extension PageLoadStatsTabExtension: NavigationResponder {

    func willStart(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame else { return }
        navigationStartTime = Date()
    }

    @MainActor
    func navigationDidFinish(_ navigation: Navigation) {
        guard navigation.navigationAction.isForMainFrame else { return }

        let url = navigation.url
        Task { @MainActor in
            await collectAndRecordMetrics(url: url)
        }
    }

    func navigation(_ navigation: Navigation, didFailWith error: WKError) {
        guard navigation.navigationAction.isForMainFrame else { return }
        reset()
    }
}

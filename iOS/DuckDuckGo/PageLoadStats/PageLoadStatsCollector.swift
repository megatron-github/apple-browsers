//
//  PageLoadStatsCollector.swift
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
import WebKit
import WebExtensions
import os.log

struct PageLoadJSMetrics {
    let loadComplete: TimeInterval
    let domComplete: TimeInterval
    let domContentLoaded: TimeInterval
    let ttfb: TimeInterval
    let firstContentfulPaint: TimeInterval?
}

@MainActor
final class PageLoadStatsCollector {

    private var navigationStartTime: Date?
    private var currentURL: URL?
    private let store: PageLoadStatsStoring
    private let webExtensionAvailabilityProvider: () -> Bool

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
        store: PageLoadStatsStoring,
        webExtensionAvailabilityProvider: @escaping () -> Bool
    ) {
        self.store = store
        self.webExtensionAvailabilityProvider = webExtensionAvailabilityProvider
    }

    func navigationDidStart(url: URL?) {
        navigationStartTime = Date()
        currentURL = url
    }

    func navigationDidFinish(webView: WKWebView) async {
        guard let startTime = navigationStartTime,
              let url = webView.url,
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
        Logger.general.debug("PageLoadStats: Recorded entry for \(url.host ?? "unknown") - \(loadDuration)ms")
        reset()
    }

    func navigationDidFail() {
        reset()
    }

    private func reset() {
        navigationStartTime = nil
        currentURL = nil
    }

    private func collectJSMetrics(webView: WKWebView) async -> PageLoadJSMetrics? {
        do {
            let result = try await webView.evaluateJavaScript(Self.metricsScript)

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
            Logger.general.debug("PageLoadStats: Failed to collect JS metrics - \(error.localizedDescription)")
            return nil
        }
    }
}

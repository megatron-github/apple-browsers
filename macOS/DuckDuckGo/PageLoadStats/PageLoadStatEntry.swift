//
//  PageLoadStatEntry.swift
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

struct PageLoadStatEntry: Codable, Identifiable {
    let id: UUID
    let url: URL
    let host: String
    let timestamp: Date

    /// Native timing: time from willStart to navigationDidFinish (in milliseconds)
    let loadDuration: TimeInterval

    /// JavaScript Performance API: domComplete - fetchStart (in milliseconds)
    let domComplete: TimeInterval?

    /// JavaScript Performance API: domContentLoadedEventEnd - fetchStart (in milliseconds)
    let domContentLoaded: TimeInterval?

    /// JavaScript Performance API: responseStart - fetchStart (in milliseconds)
    let ttfb: TimeInterval?

    /// JavaScript Performance API: first-contentful-paint startTime (in milliseconds)
    let firstContentfulPaint: TimeInterval?

    /// Whether web extension CPM was enabled at the time of measurement
    let webExtensionCPMEnabled: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        host: String,
        timestamp: Date = Date(),
        loadDuration: TimeInterval,
        domComplete: TimeInterval? = nil,
        domContentLoaded: TimeInterval? = nil,
        ttfb: TimeInterval? = nil,
        firstContentfulPaint: TimeInterval? = nil,
        webExtensionCPMEnabled: Bool
    ) {
        self.id = id
        self.url = url
        self.host = host
        self.timestamp = timestamp
        self.loadDuration = loadDuration
        self.domComplete = domComplete
        self.domContentLoaded = domContentLoaded
        self.ttfb = ttfb
        self.firstContentfulPaint = firstContentfulPaint
        self.webExtensionCPMEnabled = webExtensionCPMEnabled
    }
}

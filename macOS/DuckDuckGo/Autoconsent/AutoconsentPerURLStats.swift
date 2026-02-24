//
//  AutoconsentPerURLStats.swift
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

struct AutoconsentPerURLStatEntry: Codable, Identifiable {
    let id: UUID
    let url: URL
    let host: String
    let cmpName: String
    let isCosmetic: Bool
    let totalClicks: Int
    let duration: TimeInterval
    let timestamp: Date
    let fromExtension: Bool

    init(
        id: UUID = UUID(),
        url: URL,
        host: String,
        cmpName: String,
        isCosmetic: Bool,
        totalClicks: Int,
        duration: TimeInterval,
        timestamp: Date = Date(),
        fromExtension: Bool
    ) {
        self.id = id
        self.url = url
        self.host = host
        self.cmpName = cmpName
        self.isCosmetic = isCosmetic
        self.totalClicks = totalClicks
        self.duration = duration
        self.timestamp = timestamp
        self.fromExtension = fromExtension
    }

    init(from event: AutoconsentPopupManagedEvent) {
        self.id = UUID()
        self.url = event.url
        self.host = event.host
        self.cmpName = event.cmpName
        self.isCosmetic = event.isCosmetic
        self.totalClicks = event.totalClicks
        self.duration = event.duration
        self.timestamp = Date()
        self.fromExtension = event.source == .webExtension
    }
}

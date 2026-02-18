//
//  PromoHistoryRecord.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

struct PromoHistoryRecord: Codable, Equatable {
    let id: String
    var timesPresented: Int
    var lastPresented: Date?
    var nextEligibleDate: Date?

    var isPermanentlyDismissed: Bool {
        nextEligibleDate == .distantFuture
    }

    var isEligible: Bool {
        guard let nextEligibleDate else { return true }
        return nextEligibleDate <= Date()
    }

    init(id: String) {
        self.id = id
        self.timesPresented = 0
        self.lastPresented = nil
        self.nextEligibleDate = nil
    }
}

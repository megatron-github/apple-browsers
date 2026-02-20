//
//  PromoTypes.swift
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

/// Trigger notifications for showing a promo.
enum PromoTrigger {
    case appLaunched
    case windowBecameKey
    case newTabPageAppeared
    case itemBookmarked
}

/// How a promo is initiated.
enum PromoInitiated {
    /// Promo is initiated by the app
    case app

    /// Promo is initiated by a user action
    case user

    /// Defines the minimum hours between showing promos of this initiation type ("global cooldown")
    var cooldownHours: Int {
        switch self {
        case .app: return 24
        case .user: return 1
        }
    }
}

/// The "interruption level" of a promo.
enum PromoSeverity: Comparable {
    /// Low interruption level:
    /// - Doesn't get in the way of another action
    /// - Minimal distraction from the current task
    /// - Example: Highlighting a button via animation
    case low

    /// Medium interruption level:
    /// - May get in the way of another action
    /// - Some distraction from current task
    /// - Example: An arrow Tip highlighting a feature
    case medium

    /// High interruption level:
    /// - Does get in the way of another action
    /// - Distracts or blocks current task
    /// - Example: Set as Default dialog prompt that doesn't prevent page action
    case high
}

struct PromoType {
    /// The interruption level for a promo
    let severity: PromoSeverity

    /// The interval after which a promo times out and is auto-dismissed.
    /// Defaults to nil / no timeout.
    let timeoutInterval: TimeInterval?

    /// The result to record if the promo times out.
    /// Defaults to `.none` (eligible again on next trigger).
    let timeoutResult: PromoResult

    init(severity: PromoSeverity,
         timeoutInterval: TimeInterval? = nil,
         timeoutResult: PromoResult = .none) {
        self.severity = severity
        self.timeoutInterval = timeoutInterval
        self.timeoutResult = timeoutResult
    }
}

/// Defines the relative priority of each promo.
/// Promos must be added to this enum (in priority order) to register with `PromoService`.
enum PromoPriority: Int, Comparable {
    // Declaration order = priority order (first = highest priority)
    case nextStepsCards
    case remoteMessage
    case defaultBrowserBanner
    case defaultBrowserPopover
    case defaultBrowserInactiveModal

    static func < (lhs: PromoPriority, rhs: PromoPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Context in which the promo is shown.
/// Used for determining whether promos collide (i.e. are shown in the same context).
enum PromoContext {
    /// Shown globally, e.g. on the address/navigation bar or as a modal.
    /// Global is mutually exclusive with all other contexts.
    case global

    /// Shown only on the New Tab Page
    case newTabPage

    /// Shown only on a web page (i.e. not the New Tab Page)
    case webPage
}

/// Result recorded when a promo is dismissed or retracted.
/// Determines whether the promo is eligible to be shown again on the next trigger, and if so, after what interval (cooldown).
enum PromoResult {
    /// User engaged with the CTA. Permanently dismissed.
    case actioned

    /// User dismissed without engaging.
    /// - `.ignored()` (default, cooldown is nil) -> permanently dismissed.
    /// - `.ignored(cooldown: interval)` -> temporarily dismissed; may re-show after cooldown interval elapses.
    case ignored(cooldown: TimeInterval? = nil)

    /// Promo retracted itself or encountered an error.
    /// No state change recorded; eligible again on next trigger.
    case none
}

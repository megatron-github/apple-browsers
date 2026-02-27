//
//  PromoType.swift
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

/// The UI treatment for a promo.
/// Promo types: https://app.asana.com/1/137249556945/project/72649045549333/task/1213119765994047?focus=true
/// Attribute rules: https://app.asana.com/1/137249556945/project/72649045549333/task/1213441717569446?focus=true
enum PromoType {
    case nextSteps
    case remoteMessage
    case specialPage
    case banner
    case featureTip
    case enhancedFeatureTip
    case infoBar
    case semiModal
    case appModal
    case contentCoverSheet
    case progressiveEmphasisButton
    case inlineMessage
    case nudgeButton
    case emptyStateMessage
    case inlineTip
    case textBadge
    case dotBadge
    case menuItemHighlight
    case settingsRecommendedAction
    case custom(severity: PromoSeverity, timeoutInterval: TimeInterval? = nil, timeoutResult: PromoResult = .none)

    /// The interruption level for a promo
    var severity: PromoSeverity {
        switch self {
        case .enhancedFeatureTip,
                .appModal,
                .specialPage:
            return .high
        case .nextSteps,
                .remoteMessage,
                .banner,
                .featureTip,
                .infoBar,
                .semiModal,
                .contentCoverSheet,
                .progressiveEmphasisButton:
            return .medium
        case .inlineMessage,
                .nudgeButton,
                .emptyStateMessage,
                .inlineTip,
                .textBadge,
                .dotBadge,
                .menuItemHighlight,
                .settingsRecommendedAction:
            return .low
        case .custom(let severity, _, _):
            return severity
        }
    }

    /// The interval after which a promo times out and is auto-dismissed.
    var timeoutInterval: TimeInterval? {
        switch self {
        case .featureTip:
            return .seconds(5)
        case .enhancedFeatureTip:
            return .seconds(10)
        case .progressiveEmphasisButton:
            return .seconds(30)
        case .dotBadge:
            return .days(3)
        case .inlineTip, .textBadge, .menuItemHighlight:
            return .days(5)
        case .nudgeButton:
            return .days(7)
        case .nextSteps,
                .remoteMessage,
                .specialPage,
                .banner,
                .infoBar,
                .semiModal,
                .appModal,
                .contentCoverSheet,
                .inlineMessage,
                .emptyStateMessage,
                .settingsRecommendedAction:
            return nil
        case .custom(_, let timeoutInterval, _):
            return timeoutInterval
        }
    }

    /// The result to record if the promo times out.
    var timeoutResult: PromoResult {
        switch self {
        case .featureTip,
                .enhancedFeatureTip,
                .progressiveEmphasisButton:
            return .ignored(cooldown: .day)
        case .nudgeButton,
                .inlineTip,
                .textBadge,
                .dotBadge,
                .menuItemHighlight:
            return .ignored()
        case .nextSteps,
                .remoteMessage,
                .specialPage,
                .banner,
                .infoBar,
                .semiModal,
                .appModal,
                .contentCoverSheet,
                .inlineMessage,
                .emptyStateMessage,
                .settingsRecommendedAction:
            return .none
        case .custom(_, _, let timeoutResult):
            return timeoutResult
        }
    }
}

//
//  DefaultBrowserPromptUIProvidersProviding.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use it except in compliance with the License.
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

/// Provides UI anchors and handlers for Default Browser prompts.
/// Implemented by MainViewController so PromoService-backed Default Browser promos can present prompts.
protocol DefaultBrowserPromptUIProvidersProviding: AnyObject {

    /// View to anchor the popover below (e.g. address bar or bookmarks bar).
    func providePopoverAnchor() -> NSView?

    /// Presents the banner view controller in the main view.
    func showBanner(_ banner: BannerMessageViewController)

    /// Window to present the inactive user modal sheet over.
    func provideInactiveUserModalWindow() -> NSWindow?
}

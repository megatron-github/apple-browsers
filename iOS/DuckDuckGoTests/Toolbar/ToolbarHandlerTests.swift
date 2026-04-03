//
//  ToolbarHandlerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import XCTest
@testable import DuckDuckGo

// MARK: - ToolbarHandlerTests

class ToolbarHandlerTests: XCTestCase {

    var toolbarHandler: ToolbarHandler!
    var mockToolbar: BrowserToolbarView!
    var mockNavigatable: MockNavigatable!

    override func setUp() {
        super.setUp()
        mockToolbar = BrowserToolbarView()
        mockNavigatable = MockNavigatable(canGoBack: true, canGoForward: false)
        toolbarHandler = ToolbarHandler(toolbar: mockToolbar)
    }

    override func tearDown() {
        toolbarHandler = nil
        mockToolbar = nil
        mockNavigatable = nil
        super.tearDown()
    }

    func testUpdateToolbarWithStateNewTab() {
        toolbarHandler.updateToolbarWithState(.newTab)

        let views = mockToolbar.arrangedToolbarButtonViews
        XCTAssertEqual(views.count, 5)
        XCTAssertEqual((views[0] as? UIButton)?.accessibilityLabel, UserText.actionOpenBookmarks)
        XCTAssertEqual((views[1] as? UIButton)?.accessibilityLabel, UserText.actionOpenPasswords)
        XCTAssertEqual((views[2] as? UIButton)?.accessibilityLabel, UserText.actionForgetAll)
        XCTAssertEqual((views[3] as? UIButton)?.accessibilityLabel, UserText.tabSwitcherAccessibilityLabel)
        XCTAssertEqual((views[4] as? UIButton)?.accessibilityLabel, UserText.menuButtonHint)
    }

    func testUpdateToolbarWithStatePageLoaded() {
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))

        let views = mockToolbar.arrangedToolbarButtonViews
        XCTAssertEqual(views.count, 5)
        XCTAssertEqual((views[0] as? UIButton)?.accessibilityLabel, UserText.keyCommandBrowserBack)
        XCTAssertEqual((views[1] as? UIButton)?.accessibilityLabel, UserText.keyCommandBrowserForward)
        XCTAssertEqual((views[2] as? UIButton)?.accessibilityLabel, UserText.actionForgetAll)
        XCTAssertEqual((views[3] as? UIButton)?.accessibilityLabel, UserText.tabSwitcherAccessibilityLabel)
        XCTAssertEqual((views[4] as? UIButton)?.accessibilityLabel, UserText.menuButtonHint)

        XCTAssertTrue(toolbarHandler.backButton.isEnabled)
        XCTAssertFalse(toolbarHandler.forwardButton.isEnabled)
    }

    func testUpdateToolbarWithStateNoChange() {
        toolbarHandler.updateToolbarWithState(.newTab)
        let initialViews = mockToolbar.arrangedToolbarButtonViews

        toolbarHandler.updateToolbarWithState(.newTab)

        XCTAssertEqual(mockToolbar.arrangedToolbarButtonViews.map(ObjectIdentifier.init), initialViews.map(ObjectIdentifier.init))
    }

    func testBackButtonEnabledState() {
        mockNavigatable = MockNavigatable(canGoBack: true, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertTrue(toolbarHandler.backButton.isEnabled)

        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertFalse(toolbarHandler.backButton.isEnabled)
    }

    func testForwardButtonEnabledState() {
        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: true)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertTrue(toolbarHandler.forwardButton.isEnabled)

        mockNavigatable = MockNavigatable(canGoBack: false, canGoForward: false)
        toolbarHandler.updateToolbarWithState(.pageLoaded(currentTab: mockNavigatable))
        XCTAssertFalse(toolbarHandler.forwardButton.isEnabled)
    }
}

// MARK: - MockNavigatable

final class MockNavigatable: Navigatable {
    var canGoBack: Bool
    var canGoForward: Bool

    init(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}

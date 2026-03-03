//
//  PeekViewController.swift
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

import AppKit
import Combine

@MainActor
protocol PeekViewControllerDelegate: AnyObject {
    func peekViewControllerDidRequestSplitPane(_ controller: PeekViewController, tab: Tab)
    func peekViewControllerDidRequestNewTab(_ controller: PeekViewController, tab: Tab)
    func peekViewControllerDidDismiss(_ controller: PeekViewController, tab: Tab)
}

/// Overlay controller that displays a web page in a floating card on top of the current tab.
/// Presented when the user Shift+clicks a link ("peek" mode).
final class PeekViewController: NSViewController {

    let tab: Tab
    let parentTab: Tab
    weak var delegate: PeekViewControllerDelegate?

    private let backdropView = BackdropView()
    private let cardView = NSView()
    private let toolbar = PeekToolbarView()
    private var webViewContainer: WebViewContainerView?
    private var cancellables = Set<AnyCancellable>()

    init(tab: Tab, parentTab: Tab) {
        self.tab = tab
        self.parentTab = parentTab
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        self.view = root

        // Backdrop
        backdropView.translatesAutoresizingMaskIntoConstraints = false
        backdropView.wantsLayer = true
        backdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.4).cgColor
        backdropView.onClicked = { [weak self] in
            self?.dismissPeek()
        }
        root.addSubview(backdropView)

        NSLayoutConstraint.activate([
            backdropView.topAnchor.constraint(equalTo: root.topAnchor),
            backdropView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            backdropView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            backdropView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        // Card
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.wantsLayer = true
        cardView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cardView.layer?.cornerRadius = 12
        cardView.layer?.masksToBounds = true
        cardView.layer?.borderColor = NSColor.separatorColor.cgColor
        cardView.layer?.borderWidth = 0.5

        // Shadow on the card
        let shadowLayer = NSShadow()
        shadowLayer.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadowLayer.shadowOffset = NSSize(width: 0, height: -4)
        shadowLayer.shadowBlurRadius = 20
        cardView.shadow = shadowLayer

        root.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            cardView.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.8),
            cardView.heightAnchor.constraint(equalTo: root.heightAnchor, multiplier: 0.85)
        ])

        // Toolbar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.onSplitPane = { [weak self] in
            self?.promoteToSplitPane()
        }
        toolbar.onNewTab = { [weak self] in
            self?.promoteToNewTab()
        }
        toolbar.onClose = { [weak self] in
            self?.dismissPeek()
        }
        cardView.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: cardView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Web content area
        let container = WebViewContainerView(tab: tab, webView: tab.webView, frame: .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.autoresizingMask = []
        self.webViewContainer = container
        cardView.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        ])

        subscribeToTabTitle()
    }

    private func subscribeToTabTitle() {
        tab.$title
            .receive(on: DispatchQueue.main)
            .sink { [weak self] title in
                self?.toolbar.titleText = title ?? ""
            }
            .store(in: &cancellables)
    }

    private func promoteToSplitPane() {
        detachWebView()
        delegate?.peekViewControllerDidRequestSplitPane(self, tab: tab)
    }

    private func promoteToNewTab() {
        detachWebView()
        delegate?.peekViewControllerDidRequestNewTab(self, tab: tab)
    }

    private func dismissPeek() {
        detachWebView()
        delegate?.peekViewControllerDidDismiss(self, tab: tab)
    }

    /// Remove the web view from the card before the tab is moved elsewhere or discarded.
    private func detachWebView() {
        cancellables.removeAll()
        webViewContainer?.removeFromSuperview()
        webViewContainer = nil
    }
}

// MARK: - BackdropView

/// Transparent click-catching view used as the dimmed backdrop.
private final class BackdropView: NSView {
    var onClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClicked?()
    }

    override var acceptsFirstResponder: Bool { true }
}

//
//  PeekToolbarView.swift
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

/// Toolbar strip at the top of the peek card with title and action buttons.
final class PeekToolbarView: NSView {

    var onSplitPane: (() -> Void)?
    var onNewTab: (() -> Void)?
    var onClose: (() -> Void)?

    var titleText: String = "" {
        didSet { titleLabel.stringValue = titleText }
    }

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }()

    private lazy var splitPaneButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "Open in Split Pane")!, target: self, action: #selector(splitPanePressed))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = "Open in Split Pane"
        return button
    }()

    private lazy var newTabButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "plus.rectangle", accessibilityDescription: "Open in New Tab")!, target: self, action: #selector(newTabPressed))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = "Open in New Tab"
        return button
    }()

    private lazy var closeButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")!, target: self, action: #selector(closePressed))
        button.bezelStyle = .accessoryBarAction
        button.isBordered = false
        button.toolTip = "Close"
        return button
    }()

    private let separator: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return view
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for subview in [titleLabel, splitPaneButton, newTabButton, closeButton, separator] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            addSubview(subview)
        }

        NSLayoutConstraint.activate([
            // Close button on the left
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            // Title centered
            titleLabel.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Action buttons on the right
            newTabButton.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 8),
            newTabButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            newTabButton.widthAnchor.constraint(equalToConstant: 28),
            newTabButton.heightAnchor.constraint(equalToConstant: 28),

            splitPaneButton.leadingAnchor.constraint(equalTo: newTabButton.trailingAnchor, constant: 4),
            splitPaneButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            splitPaneButton.widthAnchor.constraint(equalToConstant: 28),
            splitPaneButton.heightAnchor.constraint(equalToConstant: 28),
            splitPaneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            // Separator at bottom
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    @objc private func splitPanePressed() {
        onSplitPane?()
    }

    @objc private func newTabPressed() {
        onNewTab?()
    }

    @objc private func closePressed() {
        onClose?()
    }
}

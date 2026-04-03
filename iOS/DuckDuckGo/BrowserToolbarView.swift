//
//  BrowserToolbarView.swift
//  DuckDuckGo
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

import UIKit

/// Custom bottom toolbar container (replaces `UIToolbar`) with widened touch targets matching legacy `HitTestingToolbar` behavior.
final class BrowserToolbarView: UIView {

    static let extendedHitWidth: CGFloat = 45
    private static let horizontalEdgePadding: CGFloat = 12
    private static let cornerRadius: CGFloat = 18
    private static let barOuterInsets = UIEdgeInsets(top: 0, left: 32, bottom: 0, right: 32)

    private let materialBackgroundView: UIVisualEffectView = {
        if #available(iOS 26.0, *) {
            let effect = UIGlassEffect(style: .regular)
            let view = UIVisualEffectView(effect: effect)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        } else {
            let effect = UIBlurEffect(style: .systemThinMaterial)
            let view = UIVisualEffectView(effect: effect)
            view.translatesAutoresizingMaskIntoConstraints = false
            return view
        }
    }()

    private let buttonStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .equalSpacing
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 0, left: BrowserToolbarView.horizontalEdgePadding, bottom: 0, right: BrowserToolbarView.horizontalEdgePadding)
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        addSubview(materialBackgroundView)
        materialBackgroundView.contentView.addSubview(buttonStack)

        materialBackgroundView.clipsToBounds = false

        if #available(iOS 26, *) {
            materialBackgroundView.cornerConfiguration =
                // .corners(radius: UICornerRadius.containerConcentric(minimum: Self.cornerRadius))
                .capsule()
        } else {
            materialBackgroundView.contentView.layer.cornerRadius = Self.cornerRadius
            materialBackgroundView.contentView.layer.cornerCurve = .continuous
        }

        materialBackgroundView.contentView.clipsToBounds = true
        materialBackgroundView.layer.shadowColor = UIColor.black.cgColor
        materialBackgroundView.layer.shadowOpacity = 0.12
        materialBackgroundView.layer.shadowRadius = 10
        materialBackgroundView.layer.shadowOffset = CGSize(width: 0, height: 4)

        NSLayoutConstraint.activate([
            materialBackgroundView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.barOuterInsets.left),
            materialBackgroundView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.barOuterInsets.right),
            materialBackgroundView.topAnchor.constraint(equalTo: topAnchor, constant: Self.barOuterInsets.top),
            materialBackgroundView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.barOuterInsets.bottom),
            buttonStack.leadingAnchor.constraint(equalTo: materialBackgroundView.contentView.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: materialBackgroundView.contentView.trailingAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: materialBackgroundView.contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var arrangedToolbarButtonViews: [UIView] {
        buttonStack.arrangedSubviews
    }

    func setToolbarButtons(_ views: [UIView]) {
        buttonStack.arrangedSubviews.forEach {
            buttonStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for view in views {
            buttonStack.addArrangedSubview(view)
        }
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in buttonStack.arrangedSubviews {
            let location = convert(point, to: subview)
            if let hit = subview.hitTest(location, with: event) {
                return hit
            }
            let extra = max(0, Self.extendedHitWidth - subview.bounds.width)
            if location.x >= -extra && location.x <= Self.extendedHitWidth
                && location.y > 0 && location.y <= subview.bounds.height {
                return subview
            }
        }
        return super.hitTest(point, with: event)
    }
}

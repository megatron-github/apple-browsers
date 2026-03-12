//
//  TabBackgroundView.swift
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

import Cocoa

/// Draws the tab background (rounded-bottom rectangle + left/right S-shaped ramps)
/// in a single `draw(_:)` pass to avoid compositing seams between layers.
final class TabBackgroundView: NSView {

    // MARK: - Rendering State

    enum State: String {
        case idle
        case highlighted
        case selected
        case dragged
    }

    // MARK: - Private Properties

    private let internalBackgroundView = TabBackgroundInternalView()
    private let internalOverlayView = ColorView(frame: .zero)
    private var state: State = .idle

    // MARK: - Public Properties

    var backgroundColor: NSColor = .clear {
        didSet {
            internalBackgroundView.backgroundColor = backgroundColor
        }
    }

    var overlayColor: NSColor = .clear {
        didSet {
            internalOverlayView.backgroundColor = overlayColor
        }
    }

    var tabCornerRadius: CGFloat = 8 {
        didSet {
            internalBackgroundView.tabCornerRadius = tabCornerRadius
        }
    }

    var rampSize: CGSize = NSSize(width: 10, height: 10) {
        didSet {
            internalBackgroundView.rampSize = rampSize
        }
    }

    // MARK: - Initializers

    override init(frame: NSRect) {
        super.init(frame: frame)

        addSubview(internalOverlayView)
        addSubview(internalBackgroundView)
        setupView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Not supported!")
    }

    override func layout() {
        super.layout()
        internalBackgroundView.frame = bounds

        let padding: CGFloat = 4
        let height = bounds.height - (padding * 2)
        let y = bounds.midY - (height / 2)
        internalOverlayView.frame = NSRect(x: bounds.origin.x + padding,
                                           y: y,
                                           width: bounds.width - (padding * 2),
                                           height: height)
    }

    func setupView() {
        wantsLayer = true
        internalOverlayView.alphaValue = 0.0
        internalOverlayView.cornerRadius = 6
    }
}

private extension TabBackgroundView.State {

    static func nextState(isMouseOver: Bool, isSelected: Bool, isDragged: Bool) -> TabBackgroundView.State {
        if isSelected {
            return .selected
        }

        if isDragged {
            return .dragged
        }

        if isMouseOver {
            return .highlighted
        }

        return .idle
    }
}

extension TabBackgroundView {

    func performAnimationIfNeeded(isSelected: Bool, isDragged: Bool, isMouseOver: Bool) {
        let nextState = State.nextState(isMouseOver: isMouseOver, isSelected: isSelected, isDragged: isDragged)

        switch state {
        case .highlighted where nextState != .highlighted:
            performOverlayAnimation(visible: false)

        case .selected where nextState != .selected:
            performBackgroundAnimation(visible: false)

        case .dragged where nextState != .dragged:
            internalBackgroundView.isDragged = false

        default:
            break
        }

        switch nextState {
        case .highlighted where state != .highlighted:
            performOverlayAnimation(visible: true)

        case .selected where state != .selected:
            performBackgroundAnimation(visible: true)

        case .dragged:
            internalBackgroundView.isDragged = true

        default:
            break
        }

        state = nextState
    }

    private func performOverlayAnimation(visible: Bool) {
        guard let layer = internalOverlayView.layer else {
            return
        }

        let duration: TimeInterval = 0.25

        let initialOpacity : Float = layer.opacity
        let finalOpacity: Float = visible ? 0.8 : 0

        let fadeAnimation: CASpringAnimation = visible
            ? .buildFadeInAnimation(duration: duration, toAlpha: finalOpacity)
            : .buildFadeOutAnimation(duration: duration, fromAlpha: initialOpacity)

        layer.add(fadeAnimation, forKey: "fadeAnimation")
        layer.opacity = finalOpacity
    }

    private func performBackgroundAnimation(visible: Bool) {
        guard let layer = internalBackgroundView.layer else {
            return
        }

        let duration: TimeInterval = 0.25
        let scaleDown: CGFloat = 0.92
        let scaleFull: CGFloat = 1
        let offsetY: CGFloat = -8

        let fadeAnimation: CASpringAnimation = visible
            ? .buildFadeInAnimation(duration: duration)
            : .buildFadeOutAnimation(duration: duration)

        let translationAnimation: CABasicAnimation = visible
            ? .buildTranslationYAnimation(duration: duration, fromValue: offsetY, toValue: .zero)
            : .buildTranslationYAnimation(duration: duration, toValue: offsetY)

        let scaleAnimation: CABasicAnimation = visible
            ? .buildScaleAnimation(duration: duration, fromValue: scaleDown, toValue: scaleFull)
            : .buildScaleAnimation(duration: duration, fromValue: scaleFull, toValue: scaleDown)

        let group = CAAnimationGroup()
        group.animations = [translationAnimation, fadeAnimation, scaleAnimation]
        group.duration = duration
        group.beginTime = CACurrentMediaTime()
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

        layer.add(group, forKey: "backgroundAnimation")
    }
}

private extension NSBezierPath {

    static func rampBezierPath(size: NSSize) -> NSBezierPath {
        let origin = NSPoint(x: size.width, y: 0)
        let center = NSPoint(x: size.width, y: size.height)

        let path = NSBezierPath()
        path.move(to: origin)
        path.line(to: .zero)
        path.appendArc(withCenter: center, radius: size.width, startAngle: 180, endAngle: 270, clockwise: false)
        path.close()
        return path
    }
}





private final class TabBackgroundInternalView: NSView {

    var backgroundColor: NSColor = .clear {
        didSet {
            guard oldValue != backgroundColor else {
                return
            }

            needsDisplay = true
        }
    }

    var rampSize: CGSize = NSSize(width: 10, height: 10) {
        didSet {
            guard oldValue != rampSize else {
                return
            }

            needsDisplay = true
        }
    }

    var tabCornerRadius: CGFloat = 8 {
        didSet {
            guard oldValue != tabCornerRadius else {
                return
            }

            needsDisplay = true
        }
    }

    var isDragged: Bool = false {
        didSet {
            guard oldValue != isDragged else {
                return
            }

            needsDisplay = true
        }
    }

    // MARK: - Private Properties

    private var backgroundRoundedCorners: [NSBezierPath.Corners] {
        isDragged ? [.topLeft, .topRight, .bottomLeft, .bottomRight] : [.bottomLeft, .bottomRight]
    }

    private var rampsAreVisible: Bool {
        !isDragged
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        backgroundColor.setFill()

        // Central Background
        let backgroundPath = NSBezierPath(roundedRect: bounds, forCorners: backgroundRoundedCorners, cornerRadius: tabCornerRadius)
        backgroundPath.fill()

        // Leading / Trailing Ramps
        if rampsAreVisible {
            drawRamps(with: context)
        }
    }

    private func drawRamps(with context: CGContext) {
        let rampPath = NSBezierPath.rampBezierPath(size: rampSize)

        // Left Ramp
        context.saveGState()
        context.scaleBy(x: -1, y: 1)

        rampPath.fill()

        context.restoreGState()

        // Right Ramp
        context.saveGState()
        context.translateBy(x: bounds.width, y: 0)

        rampPath.fill()

        context.restoreGState()
    }
}

import AppKit
import SwiftUI

@MainActor
struct NativeTrafficLightControls: NSViewRepresentable {
    func makeNSView(context: Context) -> NativeTrafficLightContainerView {
        NativeTrafficLightContainerView()
    }

    func updateNSView(_ nsView: NativeTrafficLightContainerView, context: Context) {
        nsView.installTrafficLightsIfPossible()
    }

    static func dismantleNSView(_ nsView: NativeTrafficLightContainerView, coordinator: ()) {
        nsView.detachAndHideTrafficLights()
    }
}

@MainActor
final class NativeTrafficLightContainerView: NSView {
    private static let windowButtonTypes: [NSWindow.ButtonType] = [
        .closeButton,
        .miniaturizeButton,
        .zoomButton
    ]
    private static let controlSize = NSSize(width: 60, height: 20)
    private static let buttonXOffsets: [NSWindow.ButtonType: CGFloat] = [
        .closeButton: 0,
        .miniaturizeButton: 23,
        .zoomButton: 46
    ]

    private var originalSuperviewByButton = [NSWindow.ButtonType: NSView]()
    private var originalFrameByButton = [NSWindow.ButtonType: NSRect]()
    private var originalAutoresizingMaskByButton = [NSWindow.ButtonType: NSView.AutoresizingMask]()
    private var originalTranslatesAutoresizingMaskByButton = [NSWindow.ButtonType: Bool]()
    private var hostedButtonByType = [NSWindow.ButtonType: NSButton]()
    private weak var observedWindow: NSWindow?
    private var windowObservers = [NSObjectProtocol]()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        autoresizesSubviews = false
    }

    override var intrinsicContentSize: NSSize {
        Self.controlSize
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeFullscreenChangesIfNeeded()
        installTrafficLightsIfPossible()
    }

    override func layout() {
        super.layout()
        installTrafficLightsIfPossible()
        layoutTrafficLights()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeFullscreenObservers()
            detachAndHideTrafficLights()
        }

        super.viewWillMove(toWindow: newWindow)
    }

    func installTrafficLightsIfPossible() {
        guard let window else { return }
        observeFullscreenChangesIfNeeded()

        for type in Self.windowButtonTypes {
            guard let button = window.standardWindowButton(type) else { continue }

            if button.superview !== self {
                if let existingHost = button.superview as? NativeTrafficLightContainerView {
                    existingHost.detachAndHideTrafficLights()
                }

                originalSuperviewByButton[type] = button.superview
                originalFrameByButton[type] = button.frame
                originalAutoresizingMaskByButton[type] = button.autoresizingMask
                originalTranslatesAutoresizingMaskByButton[type] = button.translatesAutoresizingMaskIntoConstraints

                button.removeFromSuperview()
                button.translatesAutoresizingMaskIntoConstraints = true
                button.autoresizingMask = []
                addSubview(button)
            }

            hostedButtonByType[type] = button
            button.isHidden = false
            button.alphaValue = 1
        }

        layoutTrafficLights()
    }

    func detachAndHideTrafficLights() {
        for type in Self.windowButtonTypes {
            guard let button = hostedButtonByType[type] ?? window?.standardWindowButton(type) else {
                continue
            }
            guard button.superview === self else { continue }

            button.removeFromSuperview()

            if let originalSuperview = originalSuperviewByButton[type] {
                originalSuperview.addSubview(button)
            }

            if let originalFrame = originalFrameByButton[type] {
                button.frame = originalFrame
            }

            if let originalAutoresizingMask = originalAutoresizingMaskByButton[type] {
                button.autoresizingMask = originalAutoresizingMask
            }

            if let originalTranslatesAutoresizingMask = originalTranslatesAutoresizingMaskByButton[type] {
                button.translatesAutoresizingMaskIntoConstraints = originalTranslatesAutoresizingMask
            }

            button.isHidden = true
            button.alphaValue = 0
            hostedButtonByType[type] = nil
        }
    }

    private func layoutTrafficLights() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            let startX = max(0, (bounds.width - Self.controlSize.width) / 2)

            for type in Self.windowButtonTypes {
                guard
                    let standardButton = window?.standardWindowButton(type),
                    let button = subviews.first(where: { $0 === standardButton }) as? NSButton,
                    let xOffset = Self.buttonXOffsets[type]
                else {
                    continue
                }

                let size = buttonSize(for: button)
                button.frame = backingAligned(
                    CGRect(
                        x: startX + xOffset,
                        y: max(0, (bounds.height - size.height) / 2),
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    private func buttonSize(for button: NSButton) -> NSSize {
        let intrinsicSize = button.intrinsicContentSize
        return NSSize(
            width: intrinsicSize.width > 0 ? intrinsicSize.width : button.frame.width,
            height: intrinsicSize.height > 0 ? intrinsicSize.height : button.frame.height
        )
    }

    private func backingAligned(_ rect: CGRect) -> CGRect {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard scale > 0 else { return rect }

        func align(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }

        return CGRect(
            x: align(rect.origin.x),
            y: align(rect.origin.y),
            width: align(rect.size.width),
            height: align(rect.size.height)
        )
    }

    private func observeFullscreenChangesIfNeeded() {
        guard let window, observedWindow !== window else { return }

        removeFullscreenObservers()
        observedWindow = window

        let notificationNames: [Notification.Name] = [
            NSWindow.willEnterFullScreenNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        for name in notificationNames {
            let observer = NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.installTrafficLightsIfPossible()
                }
            }
            windowObservers.append(observer)
        }
    }

    private func removeFullscreenObservers() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }

        windowObservers.removeAll()
        observedWindow = nil
    }
}

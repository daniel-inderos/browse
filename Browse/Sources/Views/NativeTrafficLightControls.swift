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

    private var originalSuperviewByButton = [NSWindow.ButtonType: NSView]()
    private var originalFrameByButton = [NSWindow.ButtonType: NSRect]()
    private var hostedButtonByType = [NSWindow.ButtonType: NSButton]()
    private weak var observedWindow: NSWindow?
    private var windowObservers = [NSObjectProtocol]()

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

                button.removeFromSuperview()
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

            button.isHidden = true
            button.alphaValue = 0
            hostedButtonByType[type] = nil
        }
    }

    private func layoutTrafficLights() {
        let xOrigins: [NSWindow.ButtonType: CGFloat] = [
            .closeButton: 0,
            .miniaturizeButton: 20,
            .zoomButton: 40
        ]

        for type in Self.windowButtonTypes {
            guard
                let button = subviews.first(where: { $0 === window?.standardWindowButton(type) }),
                let xOrigin = xOrigins[type]
            else {
                continue
            }

            let size = button.intrinsicContentSize
            let width = size.width > 0 ? size.width : button.frame.width
            let height = size.height > 0 ? size.height : button.frame.height
            button.frame = CGRect(
                x: xOrigin,
                y: max(0, (bounds.height - height) / 2),
                width: width,
                height: height
            )
        }
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

import AppKit
import Testing
@testable import Browse

@Suite("NativeTrafficLightControls")
@MainActor
struct NativeTrafficLightControlsTests {
    @Test("Restores button frames synchronously when the window resizes")
    func restoresButtonFramesOnResize() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let container = NativeTrafficLightContainerView(
            frame: NSRect(x: 14, y: 568, width: 60, height: 20)
        )
        window.contentView?.addSubview(container)
        container.installTrafficLightsIfPossible()

        let closeButton = try #require(window.standardWindowButton(.closeButton))
        let expectedFrame = closeButton.frame
        closeButton.setFrameOrigin(NSPoint(x: 8, y: 8))

        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: window)

        #expect(closeButton.frame == expectedFrame)
    }
}

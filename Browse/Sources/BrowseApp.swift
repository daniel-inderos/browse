import SwiftUI
import AppKit
import OSLog
import Foundation

private let logger = Logger(subsystem: "com.browse.app", category: "Lifecycle")

struct BrowserWindowConfiguration: Codable, Hashable {
    let id: UUID
    let isPrivateBrowsing: Bool
    let restoresPersistedState: Bool

    static var initialNormal: BrowserWindowConfiguration {
        BrowserWindowConfiguration(
            id: UUID(),
            isPrivateBrowsing: false,
            restoresPersistedState: true
        )
    }

    static func newNormal() -> BrowserWindowConfiguration {
        BrowserWindowConfiguration(
            id: UUID(),
            isPrivateBrowsing: false,
            restoresPersistedState: false
        )
    }

    static func newPrivate() -> BrowserWindowConfiguration {
        BrowserWindowConfiguration(
            id: UUID(),
            isPrivateBrowsing: true,
            restoresPersistedState: false
        )
    }

    static func restoredNormal(id: UUID) -> BrowserWindowConfiguration {
        BrowserWindowConfiguration(
            id: id,
            isPrivateBrowsing: false,
            restoresPersistedState: true
        )
    }
}

private struct BrowserViewModelFocusedKey: FocusedValueKey {
    typealias Value = BrowserViewModel
}

extension FocusedValues {
    var browserViewModel: BrowserViewModel? {
        get { self[BrowserViewModelFocusedKey.self] }
        set { self[BrowserViewModelFocusedKey.self] = newValue }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private func bringBrowseToFront() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func configureWindowForInlineTitleBar() {
        for window in NSApp.windows {
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = false
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            logger.info("Launched as bundle: \(bundleID, privacy: .private)")
        } else {
            logger.warning("Launched without a bundle identifier")
        }

        // Log only coarse code-signing status; team identifiers are private.
        let signingStatus = Bundle.main.infoDictionary?["TeamIdentifierPrefix"] is String
            ? "team-signed"
            : "ad-hoc"
        logger.info("Signing status: \(signingStatus, privacy: .public)")

        // ── Window setup ────────────────────────────────────────
        // Ensure Browse becomes frontmost and receives keyboard input when launched
        // (e.g. from Xcode/Terminal/Cursor), instead of focus staying with the launcher app.
        configureWindowForInlineTitleBar()
        bringBrowseToFront()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.configureWindowForInlineTitleBar()
            self?.bringBrowseToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.configureWindowForInlineTitleBar()
            self?.bringBrowseToFront()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        BrowserWindowSessionController.shared.markTerminating()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        BrowserWindowSessionController.shared.markTerminating()
        return .terminateNow
    }
}

@main
struct BrowseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Browse", for: BrowserWindowConfiguration.self) { configuration in
            BrowserWindow(
                configuration: configuration.wrappedValue
                    ?? BrowserWindowSessionController.shared.initialConfiguration()
            )
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1420, height: 800)
        .restorationBehavior(.disabled)
        .commands {
            BrowserCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

private struct BrowserCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.browserViewModel) private var browserViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(value: BrowserWindowConfiguration.newNormal())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Private Window") {
                openWindow(value: BrowserWindowConfiguration.newPrivate())
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("New Tab") {
                browserViewModel?.newTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(browserViewModel == nil)

            Button(closeCommandTitle) {
                closeActiveTabOrWindow()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(browserViewModel == nil)
        }

        CommandMenu("Tabs") {
            Button("Reopen Closed Tab") {
                browserViewModel?.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(browserViewModel?.canReopenClosedTab != true)

            Divider()

            Button("Select Tab 1") { browserViewModel?.selectTabByIndex(0) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 2") { browserViewModel?.selectTabByIndex(1) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 3") { browserViewModel?.selectTabByIndex(2) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 4") { browserViewModel?.selectTabByIndex(3) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 5") { browserViewModel?.selectTabByIndex(4) }
                .keyboardShortcut("5", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 6") { browserViewModel?.selectTabByIndex(5) }
                .keyboardShortcut("6", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 7") { browserViewModel?.selectTabByIndex(6) }
                .keyboardShortcut("7", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Tab 8") { browserViewModel?.selectTabByIndex(7) }
                .keyboardShortcut("8", modifiers: .command)
                .disabled(browserViewModel == nil)
            Button("Select Last Tab") { browserViewModel?.selectLastTab() }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(browserViewModel == nil)

            Divider()

            Button("Previous Tab") {
                browserViewModel?.selectPreviousTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(browserViewModel == nil)
            Button("Next Tab") {
                browserViewModel?.selectNextTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(browserViewModel == nil)

            Button("Previous Tab") {
                browserViewModel?.selectPreviousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(browserViewModel == nil)
            Button("Next Tab") {
                browserViewModel?.selectNextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(browserViewModel == nil)
        }

        CommandMenu("Navigation") {
            Button("Reload") {
                browserViewModel?.reloadActiveTab()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(browserViewModel == nil)

            Button("Hard Reload") {
                browserViewModel?.hardReloadActiveTab()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(browserViewModel == nil)

            Divider()

            Button("Zoom In") {
                browserViewModel?.zoomInActiveTab()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(browserViewModel?.canZoomInActiveTab != true)

            Button("Zoom Out") {
                browserViewModel?.zoomOutActiveTab()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(browserViewModel?.canZoomOutActiveTab != true)

            Button("Reset Zoom \(browserViewModel?.activePageZoomDisplayText ?? "100%")") {
                browserViewModel?.resetZoomInActiveTab()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(browserViewModel?.canResetZoomInActiveTab != true)

            Button("Back") {
                browserViewModel?.goBackInActiveTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(browserViewModel == nil)

            Button("Forward") {
                browserViewModel?.goForwardInActiveTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(browserViewModel == nil)

            Divider()

            // Keep the standard browser alternatives too.
            Button("Back") {
                browserViewModel?.goBackInActiveTab()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(browserViewModel == nil)

            Button("Forward") {
                browserViewModel?.goForwardInActiveTab()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(browserViewModel == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Focus Intent Bar") {
                NSApp.activate(ignoringOtherApps: true)
                browserViewModel?.revealIntentBarAndFocus()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(browserViewModel == nil)

            Button("Find in Page") {
                NSApp.activate(ignoringOtherApps: true)
                browserViewModel?.showFindInActiveTab()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(browserViewModel?.canFindInActiveTab != true)

            Button("Copy Current URL") {
                copyCurrentURL()
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(browserViewModel?.activeTabURL == nil)

            Button("Downloads") {
                NSApp.activate(ignoringOtherApps: true)
                browserViewModel?.toggleDownloadsPanel()
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            .disabled(browserViewModel == nil)

            Button(browserViewModel?.isChatPaneVisible == true ? "Hide Chat" : "Chat with Page") {
                browserViewModel?.toggleChatPane()
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(browserViewModel == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button(browserViewModel?.isTabBarVisible == false ? "Show Sidebar" : "Hide Sidebar") {
                browserViewModel?.toggleTabBarVisibility()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(browserViewModel == nil)
        }
    }

    private func closeActiveTabOrWindow() {
        guard let browserViewModel else { return }

        if let activeTabID = browserViewModel.activeTabID {
            browserViewModel.closeTab(activeTabID)
        } else {
            (NSApp.keyWindow ?? NSApp.mainWindow)?.performClose(nil)
        }
    }

    private var closeCommandTitle: String {
        browserViewModel?.activeTabID == nil ? "Close Window" : "Close Tab"
    }

    private func copyCurrentURL() {
        guard let url = browserViewModel?.activeTabURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        browserViewModel?.showCurrentURLCopiedIndicator()
    }
}

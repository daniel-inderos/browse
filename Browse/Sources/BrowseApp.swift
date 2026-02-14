import SwiftUI
import AppKit
import os.log
import Foundation

private let logger = Logger(subsystem: "com.browse.app", category: "Lifecycle")

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private func locateProjectRoot() -> URL? {
        // `#filePath` points to this source file in the working copy.
        // Walk up to the repository root: .../browse/Browse/Sources/BrowseApp.swift -> .../browse
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent() // Sources
        url.deleteLastPathComponent() // Browse
        url.deleteLastPathComponent() // repo root

        let scriptURL = url.appendingPathComponent("build-app.sh")
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return nil
        }
        return url
    }

    private func runAndCaptureOutput(
        executable: String,
        arguments: [String],
        workingDirectory: URL
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    }

    private func bootstrapBundleAndRelaunch() -> (success: Bool, details: String) {
        guard let projectRoot = locateProjectRoot() else {
            return (
                false,
                "Could not locate project root from runtime path. Ensure build-app.sh exists at the repo root."
            )
        }

        do {
            let build = try runAndCaptureOutput(
                executable: "/bin/bash",
                arguments: ["./build-app.sh", "--debug", "--run"],
                workingDirectory: projectRoot
            )

            if build.status == 0 {
                return (true, build.output)
            }

            return (
                false,
                """
                build-app.sh exited with status \(build.status).

                \(build.output)
                """
            )
        } catch {
            return (false, "Failed to launch build-app.sh: \(error.localizedDescription)")
        }
    }

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
        // ── Bundle validation (fail-fast) ───────────────────────
        // WebKit's multi-process architecture (WebContent, Networking helpers)
        // communicates with the host app via XPC. The helpers look up the parent
        // app's CFBundleIdentifier and validate its code signature. If either is
        // missing (e.g. running the raw SPM executable instead of the .app bundle),
        // WebKit emits sandbox/XPC errors and WKWebView will not function.
        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            let bootstrap = bootstrapBundleAndRelaunch()
            if bootstrap.success {
                logger.info("Raw executable launch detected; started bundled debug app via build-app.sh")
                NSApp.terminate(nil)
                return
            }

            let message = """
            [Browse] FATAL: Bundle.main.bundleIdentifier is nil or empty.
            
            WebKit requires a properly packaged and signed .app bundle.
            Running the raw SPM executable directly will cause WebKit's
            WebContent/Networking helper processes to fail with XPC errors.
            
            Auto-bootstrap attempt failed.
            \(bootstrap.details)
            
            To fix manually: build with ./build-app.sh and launch via:
                open .build/release/Browse.app
            """
            logger.critical("\(message)")
            // Also print to stderr so it's visible in the terminal that launched the process
            fputs(message + "\n", stderr)

            // Show a user-visible alert before terminating
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Browse cannot start"
            alert.informativeText = "This app must be launched as a .app bundle, not as a raw executable.\n\nAutomatic bootstrap failed.\n\nBuild with: ./build-app.sh\nLaunch with: open .build/release/Browse.app"
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        logger.info("Launched as bundle: \(bundleID, privacy: .public)")
        logger.info("Bundle path: \(Bundle.main.bundlePath, privacy: .public)")

        // Log code-signing status for diagnostics
        let signingInfo: String
        if let teamID = Bundle.main.infoDictionary?["TeamIdentifierPrefix"] as? String {
            signingInfo = "Team ID: \(teamID)"
        } else {
            signingInfo = "ad-hoc signed (no Team ID)"
        }
        logger.info("Signing: \(signingInfo, privacy: .public)")

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
}

@main
struct BrowseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var browserViewModel = BrowserViewModel()

    var body: some Scene {
        WindowGroup {
            BrowserWindow()
                .environment(browserViewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1420, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    browserViewModel.newTab()
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("Close Tab") {
                    if let id = browserViewModel.activeTabID {
                        browserViewModel.closeTab(id)
                    }
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Reopen Closed Tab") {
                    browserViewModel.reopenLastClosedTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Select Tab 1") { browserViewModel.selectTabByIndex(0) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Select Tab 2") { browserViewModel.selectTabByIndex(1) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Select Tab 3") { browserViewModel.selectTabByIndex(2) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Select Tab 4") { browserViewModel.selectTabByIndex(3) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Select Tab 5") { browserViewModel.selectTabByIndex(4) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Select Tab 6") { browserViewModel.selectTabByIndex(5) }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Select Tab 7") { browserViewModel.selectTabByIndex(6) }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Select Tab 8") { browserViewModel.selectTabByIndex(7) }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Select Last Tab") { browserViewModel.selectLastTab() }
                    .keyboardShortcut("9", modifiers: .command)

                Divider()

                Button("Previous Tab") {
                    browserViewModel.selectPreviousTab()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Next Tab") {
                    browserViewModel.selectNextTab()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])

                Button("Previous Tab") {
                    browserViewModel.selectPreviousTab()
                }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Button("Next Tab") {
                    browserViewModel.selectNextTab()
                }
                .keyboardShortcut(.tab, modifiers: .control)
            }

            CommandMenu("Navigation") {
                Button("Reload") {
                    browserViewModel.reloadActiveTab()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Hard Reload") {
                    browserViewModel.hardReloadActiveTab()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Back") {
                    browserViewModel.goBackInActiveTab()
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Forward") {
                    browserViewModel.goForwardInActiveTab()
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Divider()

                // Keep the standard browser alternatives too.
                Button("Back") {
                    browserViewModel.goBackInActiveTab()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    browserViewModel.goForwardInActiveTab()
                }
                .keyboardShortcut("]", modifiers: .command)
            }

            CommandGroup(after: .toolbar) {
                Button("Focus Intent Bar") {
                    NSApp.activate(ignoringOtherApps: true)
                    browserViewModel.revealIntentBarAndFocus()
                }
                .keyboardShortcut("l", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button(browserViewModel.isTabBarVisible ? "Hide Sidebar" : "Show Sidebar") {
                    browserViewModel.toggleTabBarVisibility()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

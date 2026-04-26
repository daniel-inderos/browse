import SwiftUI

@MainActor
final class BrowserWindowSessionController {
    static let shared = BrowserWindowSessionController()

    private let persistenceStore = BrowserPersistenceStore()
    private var restorableWindowIDs: [UUID]?
    private var didRestoreAdditionalWindows = false
    private var openNormalWindowIDs = Set<UUID>()

    private(set) var isTerminating = false

    private init() {}

    func markTerminating() {
        guard !isTerminating else { return }
        persistenceStore.pruneWindowStates(keepingWindowIDs: openNormalWindowIDs)
        isTerminating = true
    }

    func registerOpenWindow(configuration: BrowserWindowConfiguration) {
        guard !configuration.isPrivateBrowsing else { return }
        openNormalWindowIDs.insert(configuration.id)
    }

    func unregisterClosedWindow(configuration: BrowserWindowConfiguration) {
        guard !configuration.isPrivateBrowsing else { return }
        openNormalWindowIDs.remove(configuration.id)
        guard !isTerminating else { return }

        persistenceStore.removeWindowState(forWindowID: configuration.id)
        restorableWindowIDs?.removeAll { $0 == configuration.id }
    }

    func initialConfiguration() -> BrowserWindowConfiguration {
        guard let id = loadRestorableWindowIDs().first else {
            return .initialNormal
        }
        return .restoredNormal(id: id)
    }

    func restoreAdditionalWindowsIfNeeded(openWindow: OpenWindowAction) {
        guard !didRestoreAdditionalWindows else { return }
        didRestoreAdditionalWindows = true

        for id in loadRestorableWindowIDs().dropFirst() {
            openWindow(value: BrowserWindowConfiguration.restoredNormal(id: id))
        }
    }

    private func loadRestorableWindowIDs() -> [UUID] {
        if let restorableWindowIDs {
            return restorableWindowIDs
        }

        let ids = persistenceStore.loadRestorableWindowIDs()
        restorableWindowIDs = ids
        return ids
    }
}

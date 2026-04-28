import Foundation
import Testing
@testable import Browse

@MainActor
@Suite("SitePermissionStore")
struct SitePermissionStoreTests {
    @Test("Normal stores persist per-site decisions")
    func normalStoresPersistPerSiteDecisions() throws {
        let defaults = try makeDefaults()
        let storageKey = "site-permissions"
        let origin = try #require(SitePermissionOrigin(url: URL(string: "https://Example.com:443/path")))

        let store = SitePermissionStore(defaults: defaults, storageKey: storageKey)
        store.setDecision(.allow, for: [.camera, .microphone], origin: origin)

        let restored = SitePermissionStore(defaults: defaults, storageKey: storageKey)
        #expect(restored.decision(for: .camera, origin: origin) == .allow)
        #expect(restored.decision(for: .microphone, origin: origin) == .allow)
        #expect(restored.entries(for: origin).map(\.kind) == [.camera, .microphone])
    }

    @Test("Ephemeral stores do not write decisions")
    func ephemeralStoresDoNotWriteDecisions() throws {
        let defaults = try makeDefaults()
        let storageKey = "site-permissions"
        let origin = try #require(SitePermissionOrigin(url: URL(string: "https://example.com")))

        let store = SitePermissionStore(
            defaults: defaults,
            storageKey: storageKey,
            persistsDecisions: false
        )
        store.setDecision(.deny, for: [.popups], origin: origin)

        #expect(store.decision(for: .popups, origin: origin) == .deny)
        #expect(defaults.object(forKey: storageKey) == nil)

        let restored = SitePermissionStore(defaults: defaults, storageKey: storageKey)
        #expect(restored.decision(for: .popups, origin: origin) == nil)
    }

    @Test("Reset removes only the selected site")
    func resetRemovesOnlySelectedSite() throws {
        let defaults = try makeDefaults()
        let firstOrigin = try #require(SitePermissionOrigin(url: URL(string: "https://first.example")))
        let secondOrigin = try #require(SitePermissionOrigin(url: URL(string: "https://second.example")))
        let store = SitePermissionStore(defaults: defaults, storageKey: "site-permissions")

        store.setDecision(.allow, for: [.camera], origin: firstOrigin)
        store.setDecision(.deny, for: [.popups], origin: secondOrigin)
        store.resetDecisions(for: firstOrigin)

        #expect(store.decision(for: .camera, origin: firstOrigin) == nil)
        #expect(store.decision(for: .popups, origin: secondOrigin) == .deny)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "BrowseTests.SitePermissions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

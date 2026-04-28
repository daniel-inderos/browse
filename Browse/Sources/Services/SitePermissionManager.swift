import Foundation
import Observation
import WebKit

enum SitePermissionKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case camera
    case microphone
    case popups

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .popups: return "Pop-ups"
        }
    }

    var promptName: String {
        switch self {
        case .camera: return "your camera"
        case .microphone: return "your microphone"
        case .popups: return "pop-ups"
        }
    }

    var systemImageName: String {
        switch self {
        case .camera: return "video"
        case .microphone: return "mic"
        case .popups: return "macwindow.on.rectangle"
        }
    }

    static func mediaKinds(for type: WKMediaCaptureType) -> [SitePermissionKind] {
        switch type {
        case .camera:
            return [.camera]
        case .microphone:
            return [.microphone]
        case .cameraAndMicrophone:
            return [.camera, .microphone]
        @unknown default:
            return [.camera, .microphone]
        }
    }
}

enum SitePermissionDecision: String, Codable, Sendable {
    case allow
    case deny

    var displayName: String {
        switch self {
        case .allow: return "Allow"
        case .deny: return "Deny"
        }
    }

    var isAllowed: Bool { self == .allow }
}

struct SitePermissionOrigin: Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int?

    var storageKey: String {
        var value = "\(scheme)://\(host)"
        if let port {
            value += ":\(port)"
        }
        return value
    }

    var displayName: String {
        if let port {
            return "\(host):\(port)"
        }
        return host
    }

    init?(url: URL?) {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased() else {
            return nil
        }

        self.scheme = scheme
        self.host = host
        if let port = url.port,
           !Self.isDefaultPort(port, for: scheme) {
            self.port = port
        } else {
            self.port = nil
        }
    }

    @MainActor
    init?(securityOrigin: WKSecurityOrigin) {
        let scheme = securityOrigin.protocol.lowercased()
        let host = securityOrigin.host.lowercased()
        guard !scheme.isEmpty, !host.isEmpty else { return nil }

        self.scheme = scheme
        self.host = host
        let originPort = securityOrigin.port
        if originPort > 0,
           !Self.isDefaultPort(originPort, for: scheme) {
            self.port = originPort
        } else {
            self.port = nil
        }
    }

    private static func isDefaultPort(_ port: Int, for scheme: String) -> Bool {
        (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
    }
}

struct SitePermissionEntry: Identifiable, Equatable, Sendable {
    let kind: SitePermissionKind
    let decision: SitePermissionDecision

    var id: SitePermissionKind { kind }
}

@MainActor
@Observable
final class SitePermissionStore: @unchecked Sendable {
    static let shared = SitePermissionStore()

    private static let defaultStorageKey = "sitePermissionDecisions"

    private let defaults: UserDefaults
    private let storageKey: String
    private let persistsDecisions: Bool
    private var decisionsByOrigin: [String: [SitePermissionKind: SitePermissionDecision]]

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = SitePermissionStore.defaultStorageKey,
        persistsDecisions: Bool = true
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.persistsDecisions = persistsDecisions
        self.decisionsByOrigin = persistsDecisions
            ? Self.loadDecisions(defaults: defaults, storageKey: storageKey)
            : [:]
    }

    static func ephemeral() -> SitePermissionStore {
        SitePermissionStore(persistsDecisions: false)
    }

    func decision(for kind: SitePermissionKind, origin: SitePermissionOrigin) -> SitePermissionDecision? {
        decisionsByOrigin[origin.storageKey]?[kind]
    }

    func setDecision(
        _ decision: SitePermissionDecision,
        for kinds: [SitePermissionKind],
        origin: SitePermissionOrigin
    ) {
        guard !kinds.isEmpty else { return }
        var originDecisions = decisionsByOrigin[origin.storageKey] ?? [:]
        for kind in kinds {
            originDecisions[kind] = decision
        }
        decisionsByOrigin[origin.storageKey] = originDecisions
        persistIfNeeded()
    }

    func entries(for origin: SitePermissionOrigin?) -> [SitePermissionEntry] {
        guard let origin,
              let decisions = decisionsByOrigin[origin.storageKey] else {
            return []
        }

        return SitePermissionKind.allCases.compactMap { kind in
            guard let decision = decisions[kind] else { return nil }
            return SitePermissionEntry(kind: kind, decision: decision)
        }
    }

    func resetDecisions(for origin: SitePermissionOrigin) {
        decisionsByOrigin.removeValue(forKey: origin.storageKey)
        persistIfNeeded()
    }

    func resetAllDecisions() {
        decisionsByOrigin = [:]
        persistIfNeeded()
    }

    private func persistIfNeeded() {
        guard persistsDecisions else { return }
        defaults.set(Self.serialized(decisionsByOrigin), forKey: storageKey)
    }

    private static func loadDecisions(
        defaults: UserDefaults,
        storageKey: String
    ) -> [String: [SitePermissionKind: SitePermissionDecision]] {
        guard let rawDecisions = defaults.dictionary(forKey: storageKey) as? [String: [String: String]] else {
            return [:]
        }

        return rawDecisions.reduce(into: [:]) { result, pair in
            let decisions: [SitePermissionKind: SitePermissionDecision] = pair.value.reduce(into: [:]) { kindResult, kindPair in
                guard let kind = SitePermissionKind(rawValue: kindPair.key),
                      let decision = SitePermissionDecision(rawValue: kindPair.value) else {
                    return
                }
                kindResult[kind] = decision
            }

            if !decisions.isEmpty {
                result[pair.key] = decisions
            }
        }
    }

    private static func serialized(
        _ decisions: [String: [SitePermissionKind: SitePermissionDecision]]
    ) -> [String: [String: String]] {
        decisions.reduce(into: [:]) { result, pair in
            let originDecisions: [String: String] = pair.value.reduce(into: [:]) { kindResult, kindPair in
                kindResult[kindPair.key.rawValue] = kindPair.value.rawValue
            }

            if !originDecisions.isEmpty {
                result[pair.key] = originDecisions
            }
        }
    }
}

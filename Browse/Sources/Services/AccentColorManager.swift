import SwiftUI

// MARK: - Accent Color Manager

/// Persists the user's chosen accent color to UserDefaults and exposes it
/// as an `@Observable` property so every SwiftUI view that reads
/// `BrowseColor.accent` automatically re-renders on change.
@Observable
final class AccentColorManager: @unchecked Sendable {
    static let shared = AccentColorManager()

    // MARK: - Storage

    private static let userDefaultsKey = "accentColorHex"
    static let defaultHex = "0C50FF" // Electric Blue

    var accentHex: String {
        didSet {
            guard accentHex != oldValue else { return }
            UserDefaults.standard.set(accentHex, forKey: Self.userDefaultsKey)
        }
    }

    var accent: Color {
        Color(hex: accentHex) ?? Color(red: 0.047, green: 0.314, blue: 1.0)
    }

    private init() {
        self.accentHex = UserDefaults.standard.string(forKey: Self.userDefaultsKey)
            ?? Self.defaultHex
    }

    // MARK: - Presets

    struct Preset: Identifiable {
        let name: String
        let hex: String
        var id: String { hex }
        var color: Color { Color(hex: hex) ?? .blue }
    }

    static let presets: [Preset] = [
        Preset(name: "Electric Blue", hex: "0C50FF"),
        Preset(name: "Violet",        hex: "7B61FF"),
        Preset(name: "Magenta",       hex: "E5197F"),
        Preset(name: "Coral",         hex: "FF453A"),
        Preset(name: "Amber",         hex: "FF9500"),
        Preset(name: "Mint",          hex: "30D158"),
        Preset(name: "Teal",          hex: "00C7BE"),
        Preset(name: "Indigo",        hex: "5856D6"),
    ]
}

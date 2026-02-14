import SwiftUI

// MARK: - Type Scale

enum BrowseFont {
    // Briefing – editorial reading experience
    static let briefingHeadline    = Font.system(size: 38, weight: .bold, design: .serif)
    static let briefingTLDR        = Font.system(size: 15, weight: .regular, design: .serif)
    static let briefingSectionTitle = Font.system(size: 22, weight: .semibold, design: .default)
    static let briefingBody        = Font.system(size: 16, weight: .regular, design: .serif)
    static let briefingCaption     = Font.system(size: 12, weight: .medium, design: .default)

    // Intent bar & chrome
    static let intentBar           = Font.system(size: 14, weight: .regular, design: .default)
    static let tabTitle            = Font.system(size: 11.5, weight: .medium, design: .default)
    static let badge               = Font.system(size: 10, weight: .bold, design: .rounded)

    // Source cards
    static let sourceTitle         = Font.system(size: 13, weight: .semibold, design: .default)
    static let sourceDomain        = Font.system(size: 11, weight: .regular, design: .default)

    // Empty state
    static let emptyTitle          = Font.system(size: 28, weight: .semibold, design: .serif)
    static let emptySubtitle       = Font.system(size: 15, weight: .regular, design: .default)
    static let emptyShortcut       = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let emptyShortcutLabel  = Font.system(size: 12, weight: .regular, design: .default)

    // Follow-up conversation
    static let conversationBody    = Font.system(size: 14, weight: .regular, design: .default)
    static let conversationUser    = Font.system(size: 14, weight: .medium, design: .default)
}

// MARK: - Color Palette

enum BrowseColor {
    // Accent — user-configurable via Settings → Appearance
    static var accent: Color { AccentColorManager.shared.accent }

    // Badge colors — each semantically distinct
    static let openBadge           = Color(red: 0.13, green: 0.67, blue: 0.38)   // fresh green
    static var briefBadge: Color   { accent }                                      // follows accent
    static let searchBadge         = Color(red: 0.44, green: 0.50, blue: 0.62)   // cool slate

    // Surfaces
    static let tabBarBackground    = Color(nsColor: .windowBackgroundColor)
    static let intentBarBackground = Color(nsColor: .controlBackgroundColor)
    static let briefingBackground  = Color(nsColor: .textBackgroundColor)

    // Tints & overlays
    static let coolTint            = Color(red: 0.92, green: 0.94, blue: 0.99)   // faint blue wash
    static let surfaceHover        = Color.primary.opacity(0.05)
    static var surfaceActive: Color { accent.opacity(0.10) }
    static let surfaceSubtle       = Color.primary.opacity(0.03)
    static let borderSubtle        = Color.primary.opacity(0.08)
    static var borderFocused: Color { accent.opacity(0.50) }

    // Semantic
    static var linkColor: Color    { accent }
    static let destructive         = Color(red: 0.85, green: 0.25, blue: 0.22)
    static let success             = openBadge

    // Shadows
    static let shadowWarm          = Color(red: 0.10, green: 0.18, blue: 0.50).opacity(0.14)
    static let shadowSubtle        = Color.black.opacity(0.06)
}

// MARK: - Reusable Modifiers

extension View {
    /// Subtle warm shadow for elevated surfaces
    func warmShadow(radius: CGFloat = 8, y: CGFloat = 2) -> some View {
        self.shadow(color: BrowseColor.shadowWarm, radius: radius, x: 0, y: y)
    }

    /// Standard card styling
    func cardStyle(isHovering: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovering ? BrowseColor.surfaceHover : BrowseColor.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
            )
    }
}

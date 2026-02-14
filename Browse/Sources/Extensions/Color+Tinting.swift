import SwiftUI
import AppKit

extension Color {
    /// Creates a subtle tint by blending a source color with the background
    static func tint(from color: Color, intensity: Double = 0.08) -> Color {
        color.opacity(intensity)
    }

    // MARK: - Hex Conversion

    /// Initialize a Color from a 6-character hex string (e.g. "0C50FF").
    init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6 else { return nil }

        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        self.init(
            red:   Double((int >> 16) & 0xFF) / 255.0,
            green: Double((int >> 8)  & 0xFF) / 255.0,
            blue:  Double(int         & 0xFF) / 255.0
        )
    }

    /// Returns the color as a 6-character uppercase hex string (e.g. "0C50FF").
    var hexString: String {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        let r = Int(round(nsColor.redComponent * 255))
        let g = Int(round(nsColor.greenComponent * 255))
        let b = Int(round(nsColor.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

extension NSImage {
    /// Extract the dominant color from an image by sampling pixels
    var dominantColor: NSColor? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else { return nil }

        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0

        // Sample every 4th pixel for performance
        let step = max(1, min(width, height) / 8)
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let rgb = color.usingColorSpace(.sRGB) ?? color
                totalR += rgb.redComponent
                totalG += rgb.greenComponent
                totalB += rgb.blueComponent
                count += 1
            }
        }

        guard count > 0 else { return nil }
        return NSColor(
            red: totalR / count,
            green: totalG / count,
            blue: totalB / count,
            alpha: 1.0
        )
    }
}

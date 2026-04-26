import SwiftUI

struct FaviconView: View {
    let url: URL?
    var size: CGFloat = 16

    @Environment(BrowserViewModel.self) private var browserVM
    @State private var image: NSImage?
    @State private var didLoad = false

    private var placeholderSeed: String {
        if let host = url?.host?.lowercased() {
            return host
        }
        return url?.absoluteString.lowercased() ?? "unknown"
    }

    private var placeholderInitial: String {
        let host = url?.host?.lowercased() ?? placeholderSeed
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if let scalar = trimmed.unicodeScalars.first(where: { CharacterSet.alphanumerics.contains($0) }) {
            return String(Character(scalar)).uppercased()
        }
        return "?"
    }

    private var placeholderColor: Color {
        let hue = Double(stableHash(placeholderSeed) % 360) / 360.0
        return Color(hue: hue, saturation: 0.72, brightness: 0.82)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
            } else {
                Circle()
                    .fill(placeholderColor)
                    .overlay(
                        Text(placeholderInitial)
                            .font(.system(size: size * 0.52, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.95))
                    )
            }
        }
        .frame(width: size, height: size)
        .opacity(didLoad ? 1 : 0.6)
        .animation(.easeOut(duration: 0.2), value: didLoad)
        .task(id: url) {
            guard let url else { return }
            image = nil
            didLoad = false
            image = await FaviconService.shared.favicon(
                for: url,
                isPrivateBrowsing: browserVM.isPrivateBrowsing
            )
            didLoad = image != nil
        }
    }

    private func stableHash(_ value: String) -> UInt64 {
        // FNV-1a 64-bit for deterministic hashing across app launches.
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

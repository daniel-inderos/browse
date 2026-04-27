import SwiftUI

struct BriefingImageCarousel: View {
    let sources: [Source]
    let allowsRemoteImageLoading: Bool
    let onSourceTap: (URL) -> Void

    private var imageSources: [Source] {
        sources.filter { $0.imageURL != nil }
    }

    private let fadeWidth: CGFloat = 60

    var body: some View {
        if !imageSources.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(imageSources) { source in
                        ImageCard(
                            source: source,
                            allowsRemoteImageLoading: allowsRemoteImageLoading
                        )
                            .onTapGesture { onSourceTap(source.url) }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 2) // Prevent shadow clipping
                .frame(minWidth: 0, maxWidth: .infinity) // Center when fewer images
            }
            .mask(fadeMask)
        }
    }

    // Soft fade on left and right edges so the carousel dissolves
    // into the background instead of clipping hard at the viewport.
    private var fadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [.clear, .black],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)

            Color.black

            LinearGradient(
                colors: [.black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: fadeWidth)
        }
    }
}

// MARK: - Image Card

private struct ImageCard: View {
    let source: Source
    let allowsRemoteImageLoading: Bool

    @State private var isHovering = false

    private let cardWidth: CGFloat = 280
    private let cardHeight: CGFloat = 187 // 3:2 aspect ratio

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image layer
            if allowsRemoteImageLoading {
                AsyncImage(url: source.imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipped()
                            .transition(.opacity.animation(.easeOut(duration: 0.3)))

                    case .failure:
                        fallbackView

                    case .empty:
                        shimmerPlaceholder

                    @unknown default:
                        shimmerPlaceholder
                    }
                }
            } else {
                fallbackView
            }

            // Attribution overlay — gradient + domain
            attributionOverlay
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovering ? BrowseColor.accent.opacity(0.25) : Color.white.opacity(0.08),
                    lineWidth: 0.5
                )
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .shadow(
            color: isHovering ? BrowseColor.shadowWarm : BrowseColor.shadowSubtle,
            radius: isHovering ? 12 : 4,
            x: 0,
            y: isHovering ? 4 : 2
        )
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.2), value: isHovering)
        .contentShape(Rectangle())
    }

    // MARK: - Attribution Overlay

    private var attributionOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 6) {
                FaviconView(url: source.faviconURL ?? source.url, size: 12)

                Text(source.url.host ?? "")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .padding(.top, 24)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.0),
                        Color.black.opacity(0.55),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Shimmer Placeholder

    private var shimmerPlaceholder: some View {
        ImageShimmer()
            .frame(width: cardWidth, height: cardHeight)
    }

    // MARK: - Fallback (broken image)

    private var fallbackView: some View {
        ZStack {
            Color.primary.opacity(0.04)
            Image(systemName: "photo")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.quaternary)
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Image Shimmer

private struct ImageShimmer: View {
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.05))
            .overlay(
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.primary.opacity(0.06),
                                    Color.clear,
                                ],
                                startPoint: UnitPoint(x: shimmerOffset - 0.3, y: 0.5),
                                endPoint: UnitPoint(x: shimmerOffset + 0.3, y: 0.5)
                            )
                        )
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.8)
                    .repeatForever(autoreverses: false)
                    .delay(Double.random(in: 0...0.3))
                ) {
                    shimmerOffset = 2.0
                }
            }
    }
}

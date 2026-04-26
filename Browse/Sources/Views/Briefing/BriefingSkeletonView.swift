import SwiftUI

struct BriefingSkeletonView: View {
    let phase: BriefingPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Phase indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(BrowseColor.accent)
                    .frame(width: 6, height: 6)
                    .modifier(PulsingEffect())

                Text(phaseLabel)
                    .font(BrowseFont.briefingCaption)
                    .foregroundStyle(.tertiary)
            }

            if phase == .searching || phase == .synthesizing {
                // Skeleton lines — simulating an editorial layout
                VStack(alignment: .leading, spacing: 20) {
                    // "Headline" skeleton
                    SkeletonLine(width: 0.65, height: 28)
                    SkeletonLine(width: 0.45, height: 28)

                    // Spacer
                    Color.clear.frame(height: 4)

                    // "Body" skeleton lines
                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonLine(width: 0.9, height: 12)
                        SkeletonLine(width: 0.75, height: 12)
                        SkeletonLine(width: 0.85, height: 12)
                        SkeletonLine(width: 0.6, height: 12)
                    }

                    Color.clear.frame(height: 8)

                    // "Section title" skeleton
                    SkeletonLine(width: 0.35, height: 18)

                    VStack(alignment: .leading, spacing: 10) {
                        SkeletonLine(width: 0.85, height: 12)
                        SkeletonLine(width: 0.7, height: 12)
                        SkeletonLine(width: 0.8, height: 12)
                    }
                }
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 56)
        .frame(maxWidth: 700, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var phaseLabel: String {
        switch phase {
        case .searching: "Searching the web…"
        case .synthesizing: "Synthesizing briefing…"
        default: ""
        }
    }
}

// MARK: - Skeleton Line

struct SkeletonLine: View {
    let width: CGFloat
    var height: CGFloat = 12

    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: height / 3)
                .fill(Color.primary.opacity(0.05))
                .frame(width: geo.size.width * width)
                .overlay(
                    // Shimmer sweep
                    RoundedRectangle(cornerRadius: height / 3)
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
                        .frame(width: geo.size.width * width)
                )
        }
        .frame(height: height)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.35)
                .repeatForever(autoreverses: false)
                .delay(Double.random(in: 0...0.3))
            ) {
                shimmerOffset = 2.0
            }
        }
    }
}

// MARK: - Pulsing Effect

private struct PulsingEffect: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

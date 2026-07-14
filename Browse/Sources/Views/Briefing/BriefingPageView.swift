import SwiftUI

struct BriefingPageView: View {
    @Environment(BrowserViewModel.self) private var browserVM
    @Bindable var viewModel: BriefingViewModel
    let tabID: UUID
    let onSourceTap: (URL) -> Void
    private var privacySettings: PrivacySettingsManager { .shared }

    @State private var shouldFollowStreamingFollowUp = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var hasResolvedInitialScrollPosition = false
    @State private var isRestoringScrollPosition = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch viewModel.phase {
                    case .idle:
                        EmptyView()

                    case .searching:
                        BriefingSkeletonView(phase: .searching)

                    case .synthesizing, .complete:
                        briefingContent

                    case .error(let message):
                        errorView(message)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(ScrollTarget.followUpBottom)
                }
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($scrollPosition)
            .onScrollGeometryChange(for: BriefingScrollMetrics.self) { geometry in
                BriefingScrollMetrics(geometry)
            } action: { oldMetrics, newMetrics in
                if hasResolvedInitialScrollPosition && !isRestoringScrollPosition {
                    browserVM.reportBriefingScrollOffset(newMetrics.offsetY, tabID: tabID)
                }
                updateFollowUpAutoScroll(oldMetrics: oldMetrics, newMetrics: newMetrics)
            }
            .onAppear {
                restoreBriefingScrollPosition()
            }
            .onChange(of: viewModel.isStreamingFollowUp) { _, isStreaming in
                shouldFollowStreamingFollowUp = isStreaming
                guard isStreaming else { return }
                scrollToFollowUpBottom(using: proxy, animated: true)
            }
            .onChange(of: viewModel.streamingFollowUp) { _, _ in
                guard shouldFollowStreamingFollowUp else { return }
                scrollToFollowUpBottom(using: proxy, animated: false)
            }
            .animation(.easeOut(duration: 0.16), value: shouldShowReturnToBottomButton)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if shouldShowFloatingFollowUp {
                    floatingFollowUpBar(using: proxy)
                }
            }
            .background(briefingPageBackground)
            .environment(\.openURL, OpenURLAction { url in
                openBriefingURL(url)
            })
        }
    }

    // MARK: - Briefing Content

    private var briefingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — constrained to reading width
            BriefingHeaderView(
                query: viewModel.document.query,
                headline: viewModel.document.headline,
                tldr: viewModel.document.tldr
            )
            .padding(.top, 56)
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, alignment: .center)
            .modifier(CascadeEntrance(index: 0))

            // Image carousel — full bleed, scrolls edge to edge
            if !viewModel.document.sources.isEmpty {
                BriefingImageCarousel(
                    sources: viewModel.document.sources,
                    allowsRemoteImageLoading: allowsBriefingImageLoading,
                    onSourceTap: onSourceTap
                )
                .padding(.top, 24)
                .modifier(CascadeEntrance(index: 1))
            }

            // Sections — constrained to reading width
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(viewModel.document.sections.enumerated()), id: \.element.id) { index, section in
                    BriefingSectionView(
                        section: section,
                        sources: viewModel.document.sources,
                        onSourceTap: onSourceTap
                    )
                    .modifier(CascadeEntrance(index: index + 2))
                }

                // Streaming indicator (only during initial briefing, not follow-ups)
                if viewModel.document.isStreaming && !viewModel.isStreamingFollowUp {
                    streamingIndicator
                        .id("streaming-end")
                }
            }
            .padding(.top, 28)
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, alignment: .center)

            // Sources & follow-up — full bleed for the shelf
            if !viewModel.document.sources.isEmpty && (viewModel.phase == .complete || viewModel.isStreamingFollowUp) {
                sourcesSection
                    .padding(.top, 28)
                    .modifier(CascadeEntrance(index: viewModel.document.sections.count + 2))
            }
        }
        .padding(.bottom, 56)
    }

    private var streamingIndicator: some View {
        HStack(spacing: 8) {
            // Pulsing dot instead of spinner
            Circle()
                .fill(BrowseColor.accent)
                .frame(width: 6, height: 6)
                .modifier(PulsingDot())

            Text("Synthesizing…")
                .font(BrowseFont.briefingCaption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section divider — constrained to reading width
            HStack(spacing: 12) {
                Rectangle()
                    .fill(BrowseColor.borderSubtle)
                    .frame(height: 0.5)

                Text("SOURCES")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.quaternary)

                Rectangle()
                    .fill(BrowseColor.borderSubtle)
                    .frame(height: 0.5)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, alignment: .center)

            // Source shelf — full bleed, scrolls edge to edge
            BriefingSourceShelf(
                sources: viewModel.document.sources,
                onSourceTap: onSourceTap
            )

            if !viewModel.conversationHistory.isEmpty {
                // Follow-up history — constrained to reading width
                BriefingFollowUp(
                    viewModel: viewModel,
                    showConversationHistory: true,
                    showInput: false
                )
                .padding(.top, 12)
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 48)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var shouldShowFloatingFollowUp: Bool {
        viewModel.phase == .complete || !viewModel.conversationHistory.isEmpty
    }

    private var allowsBriefingImageLoading: Bool {
        !browserVM.isPrivateBrowsing ||
            privacySettings.allowsBriefingImageLoadingInPrivateBrowsing
    }

    private var shouldShowReturnToBottomButton: Bool {
        viewModel.isStreamingFollowUp && !shouldFollowStreamingFollowUp
    }

    private func openBriefingURL(_ url: URL) -> OpenURLAction.Result {
        if let sourceURL = BriefingCitationResolver.sourceURL(
            for: url,
            sources: viewModel.document.sources
        ) {
            onSourceTap(sourceURL)
            return .handled
        }

        guard url.scheme != "cite" else { return .handled }
        onSourceTap(url)
        return .handled
    }

    private func updateFollowUpAutoScroll(
        oldMetrics: BriefingScrollMetrics,
        newMetrics: BriefingScrollMetrics
    ) {
        guard viewModel.isStreamingFollowUp else { return }

        if shouldFollowStreamingFollowUp {
            let didScrollUp = newMetrics.offsetY < oldMetrics.offsetY - 4
            if didScrollUp && newMetrics.distanceFromBottom > 24 {
                shouldFollowStreamingFollowUp = false
            }
        } else if newMetrics.distanceFromBottom < 24 {
            shouldFollowStreamingFollowUp = true
        }
    }

    private func scrollToFollowUpBottom(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(ScrollTarget.followUpBottom, anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }

    private func restoreBriefingScrollPosition() {
        guard !hasResolvedInitialScrollPosition else { return }

        let offsetY = browserVM.briefingScrollOffset(for: tabID)
        guard offsetY > 0 else {
            hasResolvedInitialScrollPosition = true
            return
        }

        isRestoringScrollPosition = true
        scrollPosition.scrollTo(y: offsetY)

        Task { @MainActor in
            await Task.yield()
            scrollPosition.scrollTo(y: offsetY)
            await Task.yield()
            isRestoringScrollPosition = false
            hasResolvedInitialScrollPosition = true
        }
    }

    private func returnToBottomButton(using proxy: ScrollViewProxy) -> some View {
        Button {
            shouldFollowStreamingFollowUp = true
            scrollToFollowUpBottom(using: proxy, animated: true)
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BrowseColor.accent)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
                )
                .shadow(color: BrowseColor.shadowSubtle.opacity(0.5), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help("Jump to latest follow-up")
    }

    private func floatingFollowUpBar(using proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    BrowseColor.briefingBackground.opacity(0.0),
                    BrowseColor.briefingBackground.opacity(0.35),
                    BrowseColor.briefingBackground.opacity(0.82),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)

            VStack(spacing: 8) {
                if shouldShowReturnToBottomButton {
                    returnToBottomButton(using: proxy)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }

                BriefingFollowUp(
                    viewModel: viewModel,
                    showConversationHistory: false,
                    showInput: true,
                    isFloating: true
                )
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, 48)
            .padding(.bottom, 16)
            .padding(.top, 28)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.system(size: 17, weight: .semibold))

                Text(message)
                    .font(BrowseFont.briefingCaption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button(action: {
                viewModel.startGeneration()
            }) {
                Text("Try Again")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(BrowseColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Background

    private var briefingPageBackground: some View {
        ZStack {
            BrowseColor.briefingBackground
            // Very subtle warm radial glow at the top
            RadialGradient(
                colors: [
                    BrowseColor.accent.opacity(0.02),
                    Color.clear,
                ],
                center: .top,
                startRadius: 0,
                endRadius: 600
            )
        }
    }
}

// MARK: - Cascade Entrance Animation

private struct CascadeEntrance: ViewModifier {
    let index: Int
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .animation(
                .easeOut(duration: 0.5).delay(Double(index) * 0.08),
                value: hasAppeared
            )
            .onAppear { hasAppeared = true }
    }
}

// MARK: - Pulsing Dot Animation

struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .scaleEffect(isPulsing ? 0.8 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

private enum ScrollTarget {
    static let followUpBottom = "follow-up-bottom"
}

private struct BriefingScrollMetrics: Equatable {
    let offsetY: CGFloat
    let distanceFromBottom: CGFloat

    init(_ geometry: ScrollGeometry) {
        offsetY = max(0, geometry.contentOffset.y + geometry.contentInsets.top)

        let visibleHeight = geometry.containerSize.height
            - geometry.contentInsets.top
            - geometry.contentInsets.bottom
        let maxOffsetY = max(0, geometry.contentSize.height - visibleHeight)
        distanceFromBottom = max(0, maxOffsetY - offsetY)
    }
}

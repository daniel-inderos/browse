import SwiftUI

struct WebTabView: View {
    let viewModel: WebTabViewModel

    var body: some View {
        ZStack(alignment: .top) {
            WebViewRepresentable(webView: viewModel.webView)

            // Progress bar — warm accent, fades out gracefully
            if viewModel.isLoading {
                GeometryReader { geometry in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    BrowseColor.accent.opacity(0.8),
                                    BrowseColor.accent,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: geometry.size.width * viewModel.estimatedProgress,
                            height: 2.5
                        )
                        .shadow(color: BrowseColor.accent.opacity(0.3), radius: 4, y: 1)
                        .animation(.easeOut(duration: 0.25), value: viewModel.estimatedProgress)
                }
                .frame(height: 2.5)
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
            }
        }
    }
}

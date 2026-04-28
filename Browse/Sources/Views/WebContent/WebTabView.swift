import SwiftUI
import AppKit

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

            if viewModel.isFindBarVisible, viewModel.currentURL != nil {
                findBar
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing))
                    )
                    .zIndex(3)
            }
        }
        .animation(.easeOut(duration: 0.14), value: viewModel.isFindBarVisible)
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            FindBarTextField(
                text: viewModel.findQuery,
                focusRequestID: viewModel.findBarFocusRequestID,
                onChange: { viewModel.updateFindQuery($0) },
                onSubmit: { viewModel.findNext() },
                onCancel: { viewModel.closeFindBar() }
            )
            .frame(width: 210, height: 26)

            Text(viewModel.findStatusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(viewModel.findMatchCount == 0 ? BrowseColor.destructive : .secondary)
                .frame(width: 74, alignment: .trailing)
                .lineLimit(1)

            HStack(spacing: 2) {
                findButton(systemName: "chevron.up", help: "Previous Match") {
                    viewModel.findPrevious()
                }
                .disabled(viewModel.findQuery.isEmpty)

                findButton(systemName: "chevron.down", help: "Next Match") {
                    viewModel.findNext()
                }
                .disabled(viewModel.findQuery.isEmpty)

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)

                findButton(systemName: "xmark", help: "Close Find Bar") {
                    viewModel.closeFindBar()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
                .shadow(color: BrowseColor.shadowSubtle.opacity(0.7), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BrowseColor.borderSubtle, lineWidth: 0.5)
        )
    }

    private func findButton(
        systemName: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.82))
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.001))
        )
        .help(help)
    }
}

private struct FindBarTextField: NSViewRepresentable {
    let text: String
    let focusRequestID: Int
    let onChange: (String) -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 13)
        textField.placeholderString = "Find in page"
        textField.lineBreakMode = .byTruncatingTail
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.textField = textField
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.parent = self
        if textField.stringValue != text {
            textField.stringValue = text
        }
        context.coordinator.focusIfNeeded(requestID: focusRequestID)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindBarTextField
        weak var textField: NSTextField?
        private var handledFocusRequestID = 0

        init(parent: FindBarTextField) {
            self.parent = parent
        }

        func focusIfNeeded(requestID: Int) {
            guard handledFocusRequestID != requestID else { return }
            handledFocusRequestID = requestID
            DispatchQueue.main.async { [weak self] in
                guard let textField = self?.textField else { return }
                textField.window?.makeFirstResponder(textField)
                textField.currentEditor()?.selectAll(nil)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.onChange(textField.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }
}

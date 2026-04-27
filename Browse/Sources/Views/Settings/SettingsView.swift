import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    private var accentManager: AccentColorManager { .shared }
    private var privacySettings: PrivacySettingsManager { .shared }

    /// Binding that bridges the macOS `ColorPicker` (which wants `Binding<Color>`)
    /// to the hex-string storage inside `AccentColorManager`.
    private var customColorBinding: Binding<Color> {
        Binding(
            get: { AccentColorManager.shared.accent },
            set: { AccentColorManager.shared.accentHex = $0.hexString }
        )
    }

    var body: some View {
        Form {
            // ── Appearance ─────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Appearance")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Accent color used throughout the app.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(AccentColorManager.presets) { preset in
                            accentSwatch(preset)
                        }

                        Spacer()

                        // Native macOS color well for a fully custom pick
                        ColorPicker("", selection: customColorBinding, supportsOpacity: false)
                            .labelsHidden()
                            .help("Pick a custom color")
                    }

                    // Show current selection label
                    accentLabel
                }
            }

            // ── Search Suggestions ─────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search Suggestions")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Local suggestions are always available. Google autocomplete sends likely search text to Google after a short pause and is off in private windows.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle("Use Google autocomplete suggestions", isOn: Binding(
                    get: { viewModel.remoteGoogleSuggestionsEnabled },
                    set: { viewModel.setRemoteGoogleSuggestionsEnabled($0) }
                ))
            }

            // ── Claude API ─────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Claude API")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Powers briefing synthesis and follow-up conversations.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                SecureField("API Key", text: Binding(
                    get: { viewModel.claudeAPIKey },
                    set: { viewModel.setClaudeAPIKey($0) }
                ))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Test Connection") {
                        Task { await viewModel.testClaudeConnection() }
                    }
                    .disabled(viewModel.claudeAPIKey.isEmpty)

                    statusIndicator(viewModel.claudeTestStatus)
                }
            }

            // ── Exa API ────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exa Search API")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Powers web search for briefing sources.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                SecureField("API Key", text: Binding(
                    get: { viewModel.exaAPIKey },
                    set: { viewModel.setExaAPIKey($0) }
                ))
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Button("Test Connection") {
                        Task { await viewModel.testExaConnection() }
                    }
                    .disabled(viewModel.exaAPIKey.isEmpty)

                    statusIndicator(viewModel.exaTestStatus)
                }
            }

            // ── Private Browsing ───────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Private Browsing Privacy")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Private windows avoid optional third-party visual lookups unless enabled here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Toggle(
                    "Use Google favicon service in private windows",
                    isOn: Binding(
                        get: { privacySettings.allowsGoogleS2FaviconFallbackInPrivateBrowsing },
                        set: { privacySettings.allowsGoogleS2FaviconFallbackInPrivateBrowsing = $0 }
                    )
                )
                .font(.system(size: 12))
                .help("May send site domains to Google's S2 favicon endpoint to improve favicon coverage.")

                Toggle(
                    "Load briefing images in private windows",
                    isOn: Binding(
                        get: { privacySettings.allowsBriefingImageLoadingInPrivateBrowsing },
                        set: { privacySettings.allowsBriefingImageLoadingInPrivateBrowsing = $0 }
                    )
                )
                .font(.system(size: 12))
                .help("Loads source image URLs from their remote hosts while rendering private briefing cards.")
            }

            // ── Links ──────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    linkRow(label: "Get Claude API key", url: "https://console.anthropic.com")
                    linkRow(label: "Get Exa API key", url: "https://dashboard.exa.ai")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 660)
        .onAppear {
            viewModel.loadAPIKeysIfNeeded()
        }
    }

    // MARK: - Accent Swatch

    private func accentSwatch(_ preset: AccentColorManager.Preset) -> some View {
        let isSelected = accentManager.accentHex == preset.hex
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                accentManager.accentHex = preset.hex
            }
        } label: {
            Circle()
                .fill(preset.color)
                .frame(width: 22, height: 22)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? preset.color.opacity(0.5) : Color.clear,
                            lineWidth: 2
                        )
                        .frame(width: 28, height: 28)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help(preset.name)
    }

    @ViewBuilder
    private var accentLabel: some View {
        let hex = accentManager.accentHex
        if let preset = AccentColorManager.presets.first(where: { $0.hex == hex }) {
            Text(preset.name)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text("Custom")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("#\(hex)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Button("Reset") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        accentManager.accentHex = AccentColorManager.defaultHex
                    }
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(BrowseColor.accent)
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(_ status: SettingsViewModel.TestStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrowseColor.success)
                Text("Connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BrowseColor.destructive)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .transition(.opacity)
        }
    }

    private func linkRow(label: String, url: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(BrowseColor.accent)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(BrowseColor.accent.opacity(0.6))
        }
        .onTapGesture {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

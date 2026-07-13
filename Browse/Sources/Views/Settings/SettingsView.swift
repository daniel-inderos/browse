import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @State private var confirmClearBrowsingData = false
    @State private var confirmClearAIHistory = false
    private var accentManager: AccentColorManager { .shared }
    private var privacySettings: PrivacySettingsManager { .shared }
    private var retentionSettings: DataRetentionSettingsManager { .shared }

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

            // ── OpenAI API ─────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI API")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Powers briefing synthesis and follow-up conversations. Loaded from \(viewModel.apiKeyConfigurationSource).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("API Key", text: Binding(
                    get: { viewModel.openAIAPIKey },
                    set: { viewModel.setOpenAIAPIKey($0) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

                HStack(spacing: 8) {
                    Button("Test Connection") {
                        Task { await viewModel.testOpenAIConnection() }
                    }
                    .disabled(viewModel.openAIAPIKey.isEmpty)

                    statusIndicator(viewModel.openAITestStatus)
                }
            }

            // ── Exa API ────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exa Search API")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Powers web search for briefing sources. Loaded from \(viewModel.apiKeyConfigurationSource).")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SecureField("API Key", text: Binding(
                    get: { viewModel.exaAPIKey },
                    set: { viewModel.setExaAPIKey($0) }
                ))
                    .textFieldStyle(.roundedBorder)
                    .disabled(true)

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

            // ── Data Controls ──────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Control local browsing data, AI conversations, and automatic retention.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Keep browsing data", selection: Binding(
                    get: { retentionSettings.browsingDataRetention },
                    set: {
                        retentionSettings.browsingDataRetention = $0
                        try? BrowserPersistenceStore().applyRetention()
                    }
                )) {
                    ForEach(DataRetentionPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }

                Picker("Keep AI history", selection: Binding(
                    get: { retentionSettings.aiHistoryRetention },
                    set: {
                        retentionSettings.aiHistoryRetention = $0
                        try? BrowserPersistenceStore().applyRetention()
                    }
                )) {
                    ForEach(DataRetentionPeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }

                HStack(spacing: 8) {
                    Button("Clear Browsing Data", role: .destructive) {
                        confirmClearBrowsingData = true
                    }
                    .disabled(viewModel.clearBrowsingDataStatus == .running)

                    actionStatusIndicator(viewModel.clearBrowsingDataStatus)
                }

                HStack(spacing: 8) {
                    Button("Clear AI History", role: .destructive) {
                        confirmClearAIHistory = true
                    }
                    .disabled(viewModel.clearAIHistoryStatus == .running)

                    actionStatusIndicator(viewModel.clearAIHistoryStatus)
                }
            }

            // ── Links ──────────────────────────────────────────
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    linkRow(label: "Get OpenAI API key", url: "https://platform.openai.com/api-keys")
                    linkRow(label: "Get Exa API key", url: "https://dashboard.exa.ai")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 780)
        .onAppear {
            viewModel.loadAPIKeysIfNeeded()
        }
        .alert("Clear Browsing Data?", isPresented: $confirmClearBrowsingData) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Browsing Data", role: .destructive) {
                Task { await viewModel.clearBrowsingData() }
            }
        } message: {
            Text("This clears saved normal-window session data, navigation history snapshots, recently closed tabs, and WebKit website data such as cookies and cache.")
        }
        .alert("Clear AI History?", isPresented: $confirmClearAIHistory) {
            Button("Cancel", role: .cancel) {}
            Button("Clear AI History", role: .destructive) {
                viewModel.clearAIHistory()
            }
        } message: {
            Text("This clears saved page chats and briefing follow-up conversations. API keys are not removed.")
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

    @ViewBuilder
    private func actionStatusIndicator(_ status: SettingsViewModel.ActionStatus) -> some View {
        switch status {
        case .idle:
            EmptyView()
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success(let message):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BrowseColor.success)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failure(let message):
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(BrowseColor.destructive)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

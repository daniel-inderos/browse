import SwiftUI
import WebKit

@MainActor
@Observable
final class BrowserViewModel {
    private final class NotificationObserverBag {
        var observers: [NSObjectProtocol] = []

        deinit {
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    private struct RecentlyClosedTab {
        let tab: Tab
        let index: Int
        let navigationHistory: [URL]?
        let navigationHistoryIndex: Int?
    }

    private struct WebTabPersistenceSignature: Equatable {
        let title: String
        let url: URL?
        let navigationHistory: [URL]?
        let navigationHistoryIndex: Int?
        let pageZoom: Double?
    }

    var tabs: [Tab] = []
    var tabGroups: [TabGroup] = []
    var activeTabID: UUID?
    var isIntentBarFocused: Bool = false
    var intentBarFocusRequestID: Int = 0
    var isIntentBarVisible: Bool = true
    var isIntentBarRevealZoneHovered: Bool = false
    var isTabBarVisible: Bool = true
    var tabBarWidth: CGFloat = 220
    var isChatPaneVisible: Bool = false
    var chatPaneOffset: CGSize = .zero
    var chatPaneWidth: CGFloat = 380
    var chatPaneHeight: CGFloat = 480
    var chatViewModel: ChatViewModel?
    var isCurrentURLCopyIndicatorVisible: Bool = false
    var isPageZoomIndicatorVisible: Bool = false
    var pageZoomIndicatorText: String?
    var isDownloadsPanelVisible: Bool = false
    let isPrivateBrowsing: Bool
    let downloadManager: DownloadManager

    private let windowID: UUID
    private let apiKeyStore = APIKeyStore()
    private let persistenceStore: BrowserPersistenceStore
    private let allowsStatePersistence: Bool
    private let websiteDataStore: WKWebsiteDataStore
    private let sitePermissionStore: SitePermissionStore
    private let tabAnimation: Animation = .spring(response: 0.26, dampingFraction: 0.86)
    private let readingScrollHideThreshold: CGFloat = 24
    private let intentBarRevealHoverGraceDuration: TimeInterval = 0.45
    private let minChatPaneWidth: CGFloat = 300
    private let maxChatPaneWidth: CGFloat = 560
    private let minChatPaneHeight: CGFloat = 280
    private let maxChatPaneHeight: CGFloat = 720
    private var briefingScrollOffsetsByTabID: [UUID: CGFloat] = [:]
    private var intentBarRevealHoverGraceDeadline: Date = .distantPast
    private var recentlyClosedTabs: [RecentlyClosedTab] = []
    private var pageChatSnapshotsByKey: [String: PersistedPageChatSnapshot] = [:]
    private var pageChatViewModelsByKey: [String: ChatViewModel] = [:]
    private var visiblePageChatKeys: Set<String> = []
    @ObservationIgnored private var currentURLCopyIndicatorHideTask: Task<Void, Never>?
    @ObservationIgnored private var pageZoomIndicatorHideTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledPersistStateTask: Task<Void, Never>?
    @ObservationIgnored private let settingsObserverBag = NotificationObserverBag()
    private let maxRecentlyClosedTabs = 20
    private let maxPersistedPageChats = 120

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var activeTabURL: URL? {
        guard let activeTab else { return nil }
        return activeTab.webTabViewModel?.currentURL ?? activeTab.url
    }

    private var shortcutOrderedTabs: [Tab] {
        let calendar = Calendar.current
        let standardTabs = tabs.filter { !$0.isFavorite && !$0.isPinned }
        let groupedTabs = tabGroups.flatMap { group in
            standardTabs.filter { $0.groupID == group.id }
        }
        let ungroupedTabs = standardTabs.filter { $0.groupID == nil }

        return tabs.filter { $0.isFavorite }
            + tabs.filter { $0.isPinned && !$0.isFavorite }
            + groupedTabs
            + ungroupedTabs.filter {
                calendar.isDateInToday($0.lastAccessedAt)
            }
            + ungroupedTabs.filter {
                !calendar.isDateInToday($0.lastAccessedAt)
            }
    }

    var canReopenClosedTab: Bool {
        !recentlyClosedTabs.isEmpty
    }

    func showCurrentURLCopiedIndicator() {
        currentURLCopyIndicatorHideTask?.cancel()
        isCurrentURLCopyIndicatorVisible = true

        currentURLCopyIndicatorHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.16)) {
                self?.isCurrentURLCopyIndicatorVisible = false
            }
        }
    }

    func toggleDownloadsPanel() {
        let willShowDownloadsPanel = !isDownloadsPanelVisible
        isDownloadsPanelVisible = willShowDownloadsPanel
        if willShowDownloadsPanel {
            isTabBarVisible = true
        }
    }

    func hideDownloadsPanel() {
        isDownloadsPanelVisible = false
    }

    var chatTabMentionCandidates: [ChatTabMentionCandidate] {
        tabs.compactMap { tab in
            let url = tab.webTabViewModel?.currentURL ?? tab.url
            guard tab.kind == .briefing || url != nil else { return nil }

            return ChatTabMentionCandidate(
                id: tab.id,
                title: chatMentionTitle(for: tab, fallbackURL: url),
                url: url,
                kind: tab.kind,
                isActive: tab.id == activeTabID
            )
        }
    }

    var shouldShowIntentBar: Bool {
        activeTab?.kind != .briefing && isIntentBarVisible
    }

    var canFindInActiveTab: Bool {
        guard activeTab?.kind == .web else { return false }
        return activeTab?.webTabViewModel?.canFindInPage == true
    }

    var activePageZoomDisplayText: String? {
        guard activeTab?.kind == .web else { return nil }
        return activeTab?.webTabViewModel?.pageZoomDisplayText
    }

    var canZoomInActiveTab: Bool {
        guard activeTab?.kind == .web else { return false }
        return activeTab?.webTabViewModel?.canZoomIn == true
    }

    var canZoomOutActiveTab: Bool {
        guard activeTab?.kind == .web else { return false }
        return activeTab?.webTabViewModel?.canZoomOut == true
    }

    var canResetZoomInActiveTab: Bool {
        guard activeTab?.kind == .web else { return false }
        return activeTab?.webTabViewModel?.canResetZoom == true
    }

    var isFindBarVisibleInActiveTab: Bool {
        activeTab?.webTabViewModel?.isFindBarVisible == true
    }

    init(
        windowID: UUID = UUID(),
        isPrivateBrowsing: Bool = false,
        restoresPersistedState: Bool = true,
        persistenceStore: BrowserPersistenceStore = BrowserPersistenceStore(),
        downloadManager: DownloadManager = .shared
    ) {
        self.windowID = windowID
        self.isPrivateBrowsing = isPrivateBrowsing
        self.persistenceStore = persistenceStore
        self.downloadManager = downloadManager
        self.allowsStatePersistence = !isPrivateBrowsing
        self.websiteDataStore = isPrivateBrowsing ? .nonPersistent() : .default()
        self.sitePermissionStore = isPrivateBrowsing ? .ephemeral() : .shared

        observeSettingsDataActions()

        if !restoresPersistedState || !restorePersistedState() {
            newTab()
        }
    }

    // MARK: - Tab Management

    func newTab() {
        let tab = makeWebTab(title: "New Tab")
        withAnimation(tabAnimation) {
            tabs.append(tab)
            activeTabID = tab.id
        }
        tab.lastAccessedAt = Date()
        syncChatPanePresentationForActiveTab()
        isIntentBarVisible = true
        requestIntentBarFocus()
        persistState()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closedTab = tabs[index]
        let affectedGroupIDs = Set([closedTab.groupID].compactMap { $0 })
        briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
        cancelLiveBriefingWork(for: closedTab)
        rememberClosedTab(closedTab, at: index)

        withAnimation(tabAnimation) {
            tabs.remove(at: index)
            removeEmptyTabGroups(affectedGroupIDs)

            if activeTabID == id {
                if tabs.isEmpty {
                    activeTabID = nil
                    isIntentBarVisible = true
                    requestIntentBarFocus()
                } else {
                    let newIndex = min(index, tabs.count - 1)
                    activeTabID = tabs[newIndex].id
                    tabs[newIndex].lastAccessedAt = Date()
                }
            }
        }
        if let activeTab {
            loadStoredURLIfNeeded(for: activeTab)
        }
        syncChatPanePresentationForActiveTab()
        persistState()
    }

    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let closedTabs = tabs.enumerated().filter { $0.element.id != id }
        let affectedGroupIDs = Set(closedTabs.compactMap { $0.element.groupID })
        closedTabs.forEach { originalIndex, closedTab in
            briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
            cancelLiveBriefingWork(for: closedTab)
            rememberClosedTab(closedTab, at: originalIndex)
        }

        withAnimation(tabAnimation) {
            tabs.removeAll { $0.id != id }
            removeEmptyTabGroups(affectedGroupIDs)
            activeTabID = id
        }
        tabs.first?.lastAccessedAt = Date()
        if let activeTab {
            loadStoredURLIfNeeded(for: activeTab)
        }
        syncChatPanePresentationForActiveTab()
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func closeTabsBelow(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closeRangeStart = tabs.index(after: index)
        guard closeRangeStart < tabs.endIndex else { return }

        let closedTabs = Array(tabs[closeRangeStart...])
        let affectedGroupIDs = Set(closedTabs.compactMap(\.groupID))
        closedTabs.enumerated().forEach { offset, closedTab in
            briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
            cancelLiveBriefingWork(for: closedTab)
            rememberClosedTab(closedTab, at: closeRangeStart + offset)
        }

        withAnimation(tabAnimation) {
            tabs.removeSubrange(closeRangeStart...)
            removeEmptyTabGroups(affectedGroupIDs)
            if activeTabID != nil, !tabs.contains(where: { $0.id == activeTabID }) {
                activeTabID = id
            }
        }
        tabs.first(where: { $0.id == activeTabID })?.lastAccessedAt = Date()
        if let activeTab {
            loadStoredURLIfNeeded(for: activeTab)
        }
        syncChatPanePresentationForActiveTab()
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func duplicateTab(_ id: UUID) {
        guard let sourceIndex = tabs.firstIndex(where: { $0.id == id }) else { return }
        let sourceTab = tabs[sourceIndex]
        let duplicatedTab: Tab

        switch sourceTab.kind {
        case .web:
            duplicatedTab = makeWebTab(
                title: sourceTab.title,
                url: sourceTab.url,
                groupID: sourceTab.groupID,
                pageZoom: sourceTab.webTabViewModel?.pageZoom ?? sourceTab.pageZoom,
                isFavorite: sourceTab.isFavorite,
                isPinned: sourceTab.isPinned
            )
            duplicatedTab.faviconURL = sourceTab.faviconURL
            duplicatedTab.tintColor = sourceTab.tintColor
            duplicatedTab.isLoading = false
            if let currentURL = sourceTab.webTabViewModel?.currentURL ?? sourceTab.url {
                duplicatedTab.webTabViewModel?.navigate(to: currentURL)
            }

        case .briefing:
            let tab = Tab(
                kind: .briefing,
                title: sourceTab.title,
                groupID: sourceTab.groupID,
                isFavorite: sourceTab.isFavorite,
                isPinned: sourceTab.isPinned
            )
            if let sourceBriefingVM = sourceTab.briefingViewModel {
                let exaClient = ExaAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.exaAPIKey) })
                let claudeClient = ClaudeAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.claudeAPIKey) })
                let briefingVM = BriefingViewModel(
                    query: sourceBriefingVM.document.query,
                    exaClient: exaClient,
                    claudeClient: claudeClient
                )
                briefingVM.document = sourceBriefingVM.document
                briefingVM.phase = sourceBriefingVM.phase
                briefingVM.conversationHistory = sourceBriefingVM.conversationHistory
                tab.briefingViewModel = briefingVM
                wireBriefingState(for: tab, briefingVM: briefingVM)
            }
            duplicatedTab = tab
        }

        withAnimation(tabAnimation) {
            tabs.insert(duplicatedTab, at: sourceIndex + 1)
            activeTabID = duplicatedTab.id
        }
        duplicatedTab.lastAccessedAt = Date()
        syncChatPanePresentationForActiveTab()
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func reopenLastClosedTab() {
        guard let recentlyClosedTab = recentlyClosedTabs.popLast() else { return }
        let reopenedTab = recentlyClosedTab.tab

        let insertionIndex = min(recentlyClosedTab.index, tabs.count)
        withAnimation(tabAnimation) {
            tabs.insert(reopenedTab, at: insertionIndex)
            activeTabID = reopenedTab.id
        }
        reopenedTab.lastAccessedAt = Date()

        if reopenedTab.kind == .web {
            if let webVM = ensureWebTabViewModel(for: reopenedTab),
               let navigationHistory = recentlyClosedTab.navigationHistory,
               !navigationHistory.isEmpty {
                webVM.restoreNavigationHistory(
                    navigationHistory,
                    currentIndex: recentlyClosedTab.navigationHistoryIndex
                )
            }
            loadStoredURLIfNeeded(for: reopenedTab)
            let currentURL = reopenedTab.webTabViewModel?.currentURL ?? reopenedTab.url
            if currentURL == nil {
                requestIntentBarFocus()
            } else {
                isIntentBarFocused = false
            }
        } else {
            isIntentBarFocused = false
        }
        syncChatPanePresentationForActiveTab()
        persistState()
    }

    private func rememberClosedTab(_ tab: Tab, at index: Int) {
        guard !isPrivateBrowsing else { return }
        let navigationHistory = makeNavigationHistorySnapshot(for: tab)
        let navigationHistoryIndex = tab.webTabViewModel?.navigationHistorySnapshotIndex
        discardLiveWebView(for: tab)
        recentlyClosedTabs.append(
            RecentlyClosedTab(
                tab: tab,
                index: index,
                navigationHistory: navigationHistory,
                navigationHistoryIndex: navigationHistoryIndex
            )
        )
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - maxRecentlyClosedTabs)
        }
    }

    private func cancelLiveBriefingWork(for tab: Tab) {
        tab.briefingViewModel?.cancelGeneration()
    }

    func selectTab(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            activeTabID = id
        }
        if let tab = tabs.first(where: { $0.id == id }) {
            tab.lastAccessedAt = Date()
            loadStoredURLIfNeeded(for: tab)
        }
        syncChatPanePresentationForActiveTab()
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func selectTabByIndex(_ index: Int) {
        let orderedTabs = shortcutOrderedTabs
        guard index >= 0, index < orderedTabs.count else { return }
        selectTab(orderedTabs[index].id)
    }

    func selectLastTab() {
        guard let lastTab = shortcutOrderedTabs.last else { return }
        selectTab(lastTab.id)
    }

    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        guard let currentActiveTabID = activeTabID,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentActiveTabID }) else {
            selectTab(tabs[0].id)
            return
        }

        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(tabs[nextIndex].id)
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        guard let currentActiveTabID = activeTabID,
              let currentIndex = tabs.firstIndex(where: { $0.id == currentActiveTabID }) else {
            selectTab(tabs[0].id)
            return
        }

        let previousIndex = (currentIndex - 1 + tabs.count) % tabs.count
        selectTab(tabs[previousIndex].id)
    }

    func reloadActiveTab() {
        activeTab?.webTabViewModel?.reload()
    }

    func hardReloadActiveTab() {
        activeTab?.webTabViewModel?.reloadFromOrigin()
    }

    func goBackInActiveTab() {
        activeTab?.webTabViewModel?.goBack()
    }

    func goForwardInActiveTab() {
        activeTab?.webTabViewModel?.goForward()
    }

    func showFindInActiveTab() {
        guard canFindInActiveTab else { return }
        revealIntentBar()
        activeTab?.webTabViewModel?.showFindBar()
    }

    func closeFindInActiveTab() {
        activeTab?.webTabViewModel?.closeFindBar()
    }

    func findNextInActiveTab() {
        activeTab?.webTabViewModel?.findNext()
    }

    func findPreviousInActiveTab() {
        activeTab?.webTabViewModel?.findPrevious()
    }

    func zoomInActiveTab() {
        guard activeTab?.kind == .web else { return }
        changeActivePageZoom { $0.zoomIn() }
    }

    func zoomOutActiveTab() {
        guard activeTab?.kind == .web else { return }
        changeActivePageZoom { $0.zoomOut() }
    }

    func resetZoomInActiveTab() {
        guard activeTab?.kind == .web else { return }
        changeActivePageZoom { $0.resetZoom() }
    }

    private func changeActivePageZoom(_ change: (WebTabViewModel) -> Void) {
        guard let webVM = activeTab?.webTabViewModel else { return }
        let previousZoom = webVM.pageZoom
        change(webVM)
        guard webVM.pageZoom != previousZoom else { return }
        showPageZoomIndicator(for: webVM)
    }

    private func showPageZoomIndicator(for webVM: WebTabViewModel) {
        pageZoomIndicatorHideTask?.cancel()
        pageZoomIndicatorText = webVM.pageZoomDisplayText

        withAnimation(.easeOut(duration: 0.14)) {
            isPageZoomIndicatorVisible = true
        }

        pageZoomIndicatorHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.18)) {
                self?.isPageZoomIndicatorVisible = false
            }

            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.pageZoomIndicatorText = nil
        }
    }

    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned.toggle()
        persistState()
    }

    func toggleFavorite(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isFavorite.toggle()
        persistState()
    }

    @discardableResult
    func createTabGroup(title: String = "New Folder", containing tabID: UUID? = nil) -> UUID {
        let resolvedTitle = normalizedGroupTitle(title)
        let group = TabGroup(title: resolvedTitle)
        tabGroups.append(group)
        if let tabID {
            moveTab(tabID, toGroup: group.id)
        } else {
            persistState()
        }
        return group.id
    }

    func renameTabGroup(_ id: UUID, title: String) {
        guard let index = tabGroups.firstIndex(where: { $0.id == id }) else { return }
        tabGroups[index].title = normalizedGroupTitle(title)
        persistState()
    }

    func toggleTabGroupCollapsed(_ id: UUID) {
        guard let index = tabGroups.firstIndex(where: { $0.id == id }) else { return }
        tabGroups[index].isCollapsed.toggle()
        persistState()
    }

    func moveTab(_ tabID: UUID, toGroup groupID: UUID?) {
        guard let tab = tabs.first(where: { $0.id == tabID }) else { return }
        if let groupID, !tabGroups.contains(where: { $0.id == groupID }) { return }
        tab.groupID = groupID
        if let groupID,
           let groupIndex = tabGroups.firstIndex(where: { $0.id == groupID }) {
            tabGroups[groupIndex].isCollapsed = false
        }
        persistState()
    }

    func ungroupTabs(in groupID: UUID) {
        guard tabGroups.contains(where: { $0.id == groupID }) else { return }
        tabs.filter { $0.groupID == groupID }.forEach { $0.groupID = nil }
        persistState()
    }

    func deleteTabGroup(_ groupID: UUID) {
        guard let index = tabGroups.firstIndex(where: { $0.id == groupID }) else { return }
        tabs.filter { $0.groupID == groupID }.forEach { $0.groupID = nil }
        tabGroups.remove(at: index)
        persistState()
    }

    private func removeEmptyTabGroups(_ groupIDs: Set<UUID>) {
        guard !groupIDs.isEmpty else { return }
        tabGroups.removeAll { group in
            groupIDs.contains(group.id) && !tabs.contains { $0.groupID == group.id }
        }
    }

    /// Called after a gesture-driven reorder finishes to persist the new tab order.
    func commitTabReorder() {
        persistState()
    }

    func toggleTabBarVisibility() {
        isTabBarVisible.toggle()
        persistState()
    }

    func setTabBarWidth(_ width: CGFloat) {
        tabBarWidth = max(180, min(width, 360))
        persistState()
    }

    // MARK: - Chat Pane

    func toggleChatPane() {
        if isChatPaneVisible {
            closeChatPane()
        } else {
            openChatPane()
        }
    }

    func openChatPane() {
        guard let activeTab, activeTab.kind == .web,
              let webVM = activeTab.webTabViewModel,
              let pageURL = webVM.currentURL else { return }

        visiblePageChatKeys.insert(pageURL.chatSessionKey)
        activateChatContext(for: webVM)

        isChatPaneVisible = true
        if let chatViewModel {
            persistChatSnapshotIfNeeded(from: chatViewModel)
        } else {
            persistState()
        }
    }

    func closeChatPane() {
        if let pageURL = activeTab?.webTabViewModel?.currentURL {
            visiblePageChatKeys.remove(pageURL.chatSessionKey)
        }
        isChatPaneVisible = false
        if let chatViewModel {
            persistChatSnapshotIfNeeded(from: chatViewModel)
        } else {
            persistState()
        }
    }

    func clearChatForCurrentPage() {
        guard let chatViewModel, !chatViewModel.isStreaming else { return }
        chatViewModel.clearConversation()
    }

    private func clearBrowsingDataFromSettings() {
        guard !isPrivateBrowsing else { return }

        recentlyClosedTabs = []
        for tab in tabs where tab.kind == .web {
            tab.webTabViewModel?.clearNavigationHistoryKeepingCurrentPage()
        }
        persistState()
    }

    private func clearAIHistoryFromSettings() {
        guard !isPrivateBrowsing else { return }

        pageChatSnapshotsByKey = [:]
        pageChatViewModelsByKey = [:]
        visiblePageChatKeys = []
        isChatPaneVisible = false
        chatViewModel = nil
        for tab in tabs where tab.kind == .briefing {
            tab.briefingViewModel?.conversationHistory = []
        }
        persistState()
    }

    private func applyRetentionFromSettings() {
        guard !isPrivateBrowsing else { return }
        do {
            try persistenceStore.applyRetention()
        } catch {
            // Retention failures should not interrupt active browsing.
        }
    }

    func attachTabMentionToChat(_ candidate: ChatTabMentionCandidate) async {
        guard let chatViewModel,
              let tab = tabs.first(where: { $0.id == candidate.id }) else { return }

        let url = tab.webTabViewModel?.currentURL ?? tab.url ?? candidate.url
        let title = chatMentionTitle(for: tab, fallbackURL: url)
        let content: String?

        switch tab.kind {
        case .web:
            content = await tab.webTabViewModel?.extractPageContent(maxLength: 8_000)
        case .briefing:
            content = tab.briefingViewModel?.document.streamedMarkdown
        }

        chatViewModel.addMentionedTabContext(
            ChatMentionedTabContext(
                id: tab.id,
                title: title,
                url: url,
                content: content
            )
        )
    }

    func setChatPaneGeometry(offset: CGSize, width: CGFloat, height: CGFloat) {
        let clampedWidth = clamp(width, min: minChatPaneWidth, max: maxChatPaneWidth)
        let clampedHeight = clamp(height, min: minChatPaneHeight, max: maxChatPaneHeight)
        let didChange =
            chatPaneOffset != offset ||
            chatPaneWidth != clampedWidth ||
            chatPaneHeight != clampedHeight
        guard didChange else { return }

        chatPaneOffset = offset
        chatPaneWidth = clampedWidth
        chatPaneHeight = clampedHeight
        persistState()
    }

    func setChatPaneWidth(_ width: CGFloat) {
        let clampedWidth = clamp(width, min: minChatPaneWidth, max: maxChatPaneWidth)
        guard chatPaneWidth != clampedWidth else { return }

        chatPaneWidth = clampedWidth
        persistState()
    }

    // MARK: - Intent Handling

    func handleIntent(_ classification: IntentClassification) {
        switch classification {
        case .open(let url):
            openURL(url)

        case .brief(let query):
            openBriefing(query: query)

        case .search(let query):
            if query.isEmpty { return }
            openGoogleSearch(query: query)
        }

        isIntentBarFocused = false
    }

    func revealIntentBar() {
        guard activeTab?.kind != .briefing else { return }
        isIntentBarVisible = true
    }

    func setIntentBarRevealZoneHovering(_ hovering: Bool) {
        isIntentBarRevealZoneHovered = hovering
        if hovering && !isIntentBarVisible {
            revealIntentBar()
        }
        if hovering {
            intentBarRevealHoverGraceDeadline = Date().addingTimeInterval(intentBarRevealHoverGraceDuration)
        }
    }

    func revealIntentBarAndFocus() {
        guard activeTab?.kind != .briefing else {
            isIntentBarFocused = false
            isIntentBarVisible = false
            return
        }
        revealIntentBar()
        requestIntentBarFocus()
    }

    private func requestIntentBarFocus() {
        isIntentBarFocused = true
        intentBarFocusRequestID += 1
    }

    func reportBriefingScrollOffset(_ offsetY: CGFloat, tabID: UUID) {
        guard activeTabID == tabID else { return }
        guard activeTab?.kind == .briefing else { return }
        briefingScrollOffsetsByTabID[tabID] = offsetY
        isIntentBarFocused = false
        isIntentBarVisible = false
    }

    func briefingScrollOffset(for tabID: UUID) -> CGFloat {
        briefingScrollOffsetsByTabID[tabID] ?? 0
    }

    func hideIntentBarIfReadingPositionActive() {
        guard isIntentBarVisible else { return }
        guard !isFindBarVisibleInActiveTab else { return }
        guard !isIntentBarRevealZoneHovered else { return }
        guard Date() >= intentBarRevealHoverGraceDeadline else { return }
        if shouldHideIntentBarForCurrentContext() {
            isIntentBarVisible = false
        }
    }

    private func openURL(_ url: URL) {
        if let activeTab, activeTab.kind == .web {
            if activeTab.webTabViewModel == nil {
                let vm = WebTabViewModel(
                    websiteDataStore: websiteDataStore,
                    downloadManager: downloadManager,
                    isPrivateBrowsing: isPrivateBrowsing,
                    sitePermissionStore: sitePermissionStore
                )
                vm.restorePageZoom(activeTab.pageZoom)
                activeTab.webTabViewModel = vm
                wireWebTabState(for: activeTab, webVM: vm)
            }
            activeTab.webTabViewModel?.navigate(to: url)
            activeTab.url = url
            activeTab.title = url.host ?? url.absoluteString
            activeTab.lastAccessedAt = Date()
        } else {
            let tab = makeWebTab(title: url.host ?? "Loading...", url: url, groupID: activeTab?.groupID)
            withAnimation(tabAnimation) {
                tabs.append(tab)
                activeTabID = tab.id
            }
            tab.lastAccessedAt = Date()
            tab.webTabViewModel?.navigate(to: url)
        }
        persistState()
    }

    private func openGoogleSearch(query: String) {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components?.url else { return }
        openURL(url)
    }

    private func openBriefing(query: String) {
        let exaClient = ExaAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.exaAPIKey) })
        let claudeClient = ClaudeAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.claudeAPIKey) })
        let vm = BriefingViewModel(query: query, exaClient: exaClient, claudeClient: claudeClient)

        if let activeTab, canReuseAsNewTab(activeTab) {
            activeTab.kind = .briefing
            activeTab.title = query
            activeTab.url = nil
            activeTab.faviconURL = nil
            activeTab.tintColor = nil
            activeTab.isLoading = false
            activeTab.webTabViewModel = nil
            activeTab.briefingViewModel = vm
            wireBriefingState(for: activeTab, briefingVM: vm)
            activeTab.lastAccessedAt = Date()
        } else {
            let tab = Tab(kind: .briefing, title: query, groupID: activeTab?.groupID)
            tab.briefingViewModel = vm
            wireBriefingState(for: tab, briefingVM: vm)
            withAnimation(tabAnimation) {
                tabs.append(tab)
                activeTabID = tab.id
            }
            tab.lastAccessedAt = Date()
        }

        syncChatPanePresentationForActiveTab()
        persistState()
        vm.startGeneration()
    }

    private func canReuseAsNewTab(_ tab: Tab) -> Bool {
        guard tab.kind == .web else { return false }
        guard tab.url == nil else { return false }

        guard let webVM = tab.webTabViewModel else { return true }
        return webVM.currentURL == nil
    }

    private func chatMentionTitle(for tab: Tab, fallbackURL: URL?) -> String {
        if tab.kind == .briefing,
           let query = tab.briefingViewModel?.document.query,
           !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return query
        }

        if let pageTitle = tab.webTabViewModel?.pageTitle,
           !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           pageTitle != "New Tab" {
            return pageTitle
        }

        if !tab.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           tab.title != "New Tab" {
            return tab.title
        }

        return fallbackURL?.displayHost ?? "Untitled Tab"
    }

    private func normalizedGroupTitle(_ title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? "New Folder" : trimmedTitle
    }

    // MARK: - Source Navigation

    func openSourceInNewTab(_ url: URL, activates: Bool = true) {
        let tab = makeWebTab(title: url.host ?? "Loading...", url: url, groupID: activeTab?.groupID)
        withAnimation(tabAnimation) {
            tabs.append(tab)
            if activates {
                activeTabID = tab.id
            }
        }
        tab.lastAccessedAt = Date()
        if activates {
            isIntentBarVisible = true
        }
        tab.webTabViewModel?.navigate(to: url)
        persistState()
    }

    // MARK: - Persistence

    private func restorePersistedState() -> Bool {
        guard allowsStatePersistence else { return false }
        guard let persisted = persistenceStore.loadWindowState(forWindowID: windowID) else { return false }
        guard !persisted.tabs.isEmpty else { return false }
        pageChatSnapshotsByKey = [:]
        pageChatViewModelsByKey = [:]
        visiblePageChatKeys = []
        if let persistedPageChats = persisted.pageChats {
            for snapshot in persistedPageChats {
                let key = snapshot.pageURL.chatSessionKey
                if let existing = pageChatSnapshotsByKey[key],
                   existing.updatedAt > snapshot.updatedAt {
                    continue
                }
                pageChatSnapshotsByKey[key] = snapshot
                if snapshot.isSidebarVisible == true {
                    visiblePageChatKeys.insert(key)
                }
            }
        }

        tabGroups = (persisted.tabGroups ?? []).map { snapshot in
            TabGroup(
                id: snapshot.id,
                title: normalizedGroupTitle(snapshot.title),
                isCollapsed: snapshot.isCollapsed,
                createdAt: snapshot.createdAt
            )
        }
        let validGroupIDs = Set(tabGroups.map(\.id))
        let restoredActiveTabID = persisted.activeTabID.flatMap { id in
            persisted.tabs.contains(where: { $0.id == id }) ? id : nil
        } ?? persisted.tabs.first?.id

        tabs = persisted.tabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                kind: snapshot.kind,
                title: snapshot.title,
                url: snapshot.url,
                groupID: snapshot.groupID.flatMap { validGroupIDs.contains($0) ? $0 : nil },
                pageZoom: snapshot.pageZoom,
                isFavorite: snapshot.isFavorite ?? false,
                isPinned: snapshot.isPinned,
                createdAt: snapshot.createdAt,
                lastAccessedAt: snapshot.lastAccessedAt
            )

            if tab.kind == .web {
                let webVM = WebTabViewModel(
                    websiteDataStore: websiteDataStore,
                    downloadManager: downloadManager,
                    isPrivateBrowsing: isPrivateBrowsing,
                    sitePermissionStore: sitePermissionStore
                )
                webVM.restorePageZoom(snapshot.pageZoom)
                tab.webTabViewModel = webVM
                let history = restoredNavigationHistory(from: snapshot)
                let historyIndex = restoredNavigationHistoryIndex(from: snapshot, history: history)
                webVM.restoreNavigationHistory(history, currentIndex: historyIndex)
                wireWebTabState(for: tab, webVM: webVM)
                if let url = restoredCurrentURL(from: snapshot, history: history, historyIndex: historyIndex) {
                    tab.url = url
                }
            } else if tab.kind == .briefing {
                let exaClient = ExaAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.exaAPIKey) })
                let claudeClient = ClaudeAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.claudeAPIKey) })
                let briefingVM = BriefingViewModel(
                    query: snapshot.briefing?.document.query ?? snapshot.title,
                    exaClient: exaClient,
                    claudeClient: claudeClient
                )

                if let briefingSnapshot = snapshot.briefing {
                    var document = briefingSnapshot.document
                    document.isStreaming = false
                    briefingVM.document = document
                    briefingVM.phase = makeBriefingPhase(from: briefingSnapshot.phase)
                    briefingVM.conversationHistory = briefingSnapshot.conversationHistory
                }

                tab.briefingViewModel = briefingVM
                wireBriefingState(for: tab, briefingVM: briefingVM)
            }

            return tab
        }

        activeTabID = restoredActiveTabID

        isTabBarVisible = persisted.isTabBarVisible
        tabBarWidth = max(180, min(CGFloat(persisted.tabBarWidth), 360))
        chatPaneOffset = CGSize(
            width: CGFloat(persisted.chatPaneOffsetX ?? 0),
            height: CGFloat(persisted.chatPaneOffsetY ?? 0)
        )
        chatPaneWidth = clamp(
            CGFloat(persisted.chatPaneWidth ?? Double(chatPaneWidth)),
            min: minChatPaneWidth,
            max: maxChatPaneWidth
        )
        chatPaneHeight = clamp(
            CGFloat(persisted.chatPaneHeight ?? Double(chatPaneHeight)),
            min: minChatPaneHeight,
            max: maxChatPaneHeight
        )
        if let activeTab {
            loadStoredURLIfNeeded(for: activeTab)
        }
        syncChatPanePresentationForActiveTab()
        return true
    }

    private func makePersistedState() -> PersistedBrowserState {
        let tabSnapshots = tabs.map(makePersistedTabSnapshot)
        return PersistedBrowserState(
            tabs: tabSnapshots,
            tabGroups: tabGroups.map { group in
                PersistedTabGroupSnapshot(
                    id: group.id,
                    title: group.title,
                    isCollapsed: group.isCollapsed,
                    createdAt: group.createdAt
                )
            },
            activeTabID: activeTabID,
            isTabBarVisible: isTabBarVisible,
            tabBarWidth: Double(tabBarWidth),
            chatPaneWidth: Double(chatPaneWidth),
            chatPaneHeight: Double(chatPaneHeight),
            chatPaneOffsetX: Double(chatPaneOffset.width),
            chatPaneOffsetY: Double(chatPaneOffset.height),
            pageChats: makePersistedPageChatSnapshots()
        )
    }

    private func persistState() {
        guard allowsStatePersistence else { return }
        scheduledPersistStateTask?.cancel()
        scheduledPersistStateTask = nil
        writePersistedState()
    }

    private func schedulePersistState() {
        guard allowsStatePersistence else { return }
        scheduledPersistStateTask?.cancel()
        scheduledPersistStateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.scheduledPersistStateTask = nil
            self?.writePersistedState()
        }
    }

    private func writePersistedState() {
        persistenceStore.save(makePersistedState(), forWindowID: windowID)
    }

    private func observeSettingsDataActions() {
        let center = NotificationCenter.default
        settingsObserverBag.observers = [
            center.addObserver(
                forName: .browseClearBrowsingDataRequested,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.clearBrowsingDataFromSettings()
                }
            },
            center.addObserver(
                forName: .browseClearAIHistoryRequested,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.clearAIHistoryFromSettings()
                }
            },
            center.addObserver(
                forName: .browseDataRetentionSettingsChanged,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.applyRetentionFromSettings()
                }
            }
        ]
    }

    private func restoredNavigationHistory(from snapshot: PersistedTabSnapshot) -> [URL] {
        if let navigationHistory = snapshot.navigationHistory, !navigationHistory.isEmpty {
            return navigationHistory
        }
        return snapshot.url.map { [$0] } ?? []
    }

    private func restoredNavigationHistoryIndex(
        from snapshot: PersistedTabSnapshot,
        history: [URL]
    ) -> Int? {
        guard !history.isEmpty else { return nil }
        let fallbackIndex = snapshot.navigationHistoryIndex ?? history.index(before: history.endIndex)
        return max(0, min(fallbackIndex, history.index(before: history.endIndex)))
    }

    private func restoredCurrentURL(
        from snapshot: PersistedTabSnapshot,
        history: [URL],
        historyIndex: Int?
    ) -> URL? {
        if let historyIndex, history.indices.contains(historyIndex) {
            return history[historyIndex]
        }
        return snapshot.url
    }

    private func makeNavigationHistorySnapshot(for tab: Tab) -> [URL]? {
        if let history = tab.webTabViewModel?.navigationHistorySnapshot, !history.isEmpty {
            return history
        }
        return tab.url.map { [$0] }
    }

    private func makePersistedTabSnapshot(for tab: Tab) -> PersistedTabSnapshot {
        PersistedTabSnapshot(
            id: tab.id,
            kind: tab.kind,
            title: tab.title,
            url: tab.url,
            groupID: tab.groupID,
            navigationHistory: makeNavigationHistorySnapshot(for: tab),
            navigationHistoryIndex: tab.webTabViewModel?.navigationHistorySnapshotIndex,
            pageZoom: persistedPageZoom(for: tab),
            isFavorite: tab.isFavorite,
            isPinned: tab.isPinned,
            createdAt: tab.createdAt,
            lastAccessedAt: tab.lastAccessedAt,
            briefing: makeBriefingSnapshot(for: tab)
        )
    }

    private func webTabPersistenceSignature(for tab: Tab) -> WebTabPersistenceSignature {
        WebTabPersistenceSignature(
            title: tab.title,
            url: tab.url,
            navigationHistory: makeNavigationHistorySnapshot(for: tab),
            navigationHistoryIndex: tab.webTabViewModel?.navigationHistorySnapshotIndex,
            pageZoom: tab.pageZoom
        )
    }

    private func persistedPageZoom(for tab: Tab) -> Double? {
        guard tab.kind == .web else { return nil }
        let zoom = tab.webTabViewModel?.pageZoom ?? tab.pageZoom ?? WebTabViewModel.defaultPageZoom
        return zoom == WebTabViewModel.defaultPageZoom ? nil : zoom
    }

    private func makePersistedPageChatSnapshots() -> [PersistedPageChatSnapshot]? {
        var snapshotsByKey = pageChatSnapshotsByKey

        // Ensure in-memory chats are not dropped if they changed very recently.
        for (key, chatVM) in pageChatViewModelsByKey {
            guard let pageURL = chatVM.pageURL else { continue }
            let shouldKeepSnapshot =
                !chatVM.conversationHistory.isEmpty ||
                visiblePageChatKeys.contains(key)
            guard shouldKeepSnapshot else {
                snapshotsByKey.removeValue(forKey: key)
                continue
            }

            let title = resolvedChatPageTitle(for: chatVM, pageURL: pageURL)
            snapshotsByKey[key] = PersistedPageChatSnapshot(
                pageURL: pageURL,
                pageTitle: title,
                conversationHistory: chatVM.conversationHistory,
                updatedAt: Date(),
                isSidebarVisible: visiblePageChatKeys.contains(key) ? true : nil
            )
        }

        snapshotsByKey = snapshotsByKey.mapValues { snapshot in
            let key = snapshot.pageURL.chatSessionKey
            return PersistedPageChatSnapshot(
                pageURL: snapshot.pageURL,
                pageTitle: snapshot.pageTitle,
                conversationHistory: snapshot.conversationHistory,
                updatedAt: snapshot.updatedAt,
                isSidebarVisible: visiblePageChatKeys.contains(key) ? true : nil
            )
        }

        let snapshots = snapshotsByKey.values
            .filter { !$0.conversationHistory.isEmpty || $0.isSidebarVisible == true }
            .sorted { $0.updatedAt > $1.updatedAt }

        guard !snapshots.isEmpty else { return nil }
        return Array(snapshots.prefix(maxPersistedPageChats))
    }

    private func makeWebTab(
        title: String,
        url: URL? = nil,
        id: UUID = UUID(),
        groupID: UUID? = nil,
        pageZoom: Double? = nil,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) -> Tab {
        let tab = Tab(
            id: id,
            kind: .web,
            title: title,
            url: url,
            groupID: groupID,
            pageZoom: pageZoom,
            isFavorite: isFavorite,
            isPinned: isPinned,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
        let webVM = WebTabViewModel(
            websiteDataStore: websiteDataStore,
            downloadManager: downloadManager,
            isPrivateBrowsing: isPrivateBrowsing,
            sitePermissionStore: sitePermissionStore
        )
        webVM.restorePageZoom(pageZoom)
        tab.webTabViewModel = webVM
        wireWebTabState(for: tab, webVM: webVM)
        return tab
    }

    @discardableResult
    private func ensureWebTabViewModel(for tab: Tab) -> WebTabViewModel? {
        guard tab.kind == .web else { return nil }
        if let webVM = tab.webTabViewModel {
            return webVM
        }

        let webVM = WebTabViewModel(
            websiteDataStore: websiteDataStore,
            downloadManager: downloadManager,
            isPrivateBrowsing: isPrivateBrowsing,
            sitePermissionStore: sitePermissionStore
        )
        webVM.restorePageZoom(tab.pageZoom)
        tab.webTabViewModel = webVM
        wireWebTabState(for: tab, webVM: webVM)
        return webVM
    }

    private func loadStoredURLIfNeeded(for tab: Tab) {
        guard let webVM = ensureWebTabViewModel(for: tab) else { return }
        guard webVM.currentURL == nil, let url = tab.url else { return }
        webVM.navigate(to: url)
    }

    private func discardLiveWebView(for tab: Tab) {
        guard tab.kind == .web, let webVM = tab.webTabViewModel else { return }
        syncWebTabState(tab, from: webVM)
        webVM.closePage()
        tab.isLoading = false
        tab.webTabViewModel = nil
    }

    private func wireWebTabState(for tab: Tab, webVM: WebTabViewModel) {
        webVM.onOpenURLInNewTab = { [weak self] url, activates in
            self?.openSourceInNewTab(url, activates: activates)
        }
        webVM.onStateChange = { [weak self, weak tab, weak webVM] in
            guard let self, let tab, let webVM else { return }
            let persistedBefore = self.webTabPersistenceSignature(for: tab)
            self.syncWebTabState(tab, from: webVM)
            let persistedAfter = self.webTabPersistenceSignature(for: tab)
            if persistedAfter != persistedBefore {
                self.schedulePersistState()
            }

            // Keep chat pane tied to the current page URL for the active tab.
            if tab.id == self.activeTabID {
                self.syncChatPanePresentation(for: webVM)
            }
        }
        webVM.onScrollPositionChange = { [weak self, weak tab] offsetY in
            guard let self, let tab else { return }
            guard tab.id == self.activeTabID else { return }
            self.updateIntentBarVisibility(for: offsetY)
        }
    }

    private func wireBriefingState(for tab: Tab, briefingVM: BriefingViewModel) {
        briefingVM.onStateChange = { [weak self, weak tab, weak briefingVM] in
            guard let self, let tab, let briefingVM else { return }
            tab.title = briefingVM.document.query
            self.persistState()
        }
    }

    private func syncChatPanePresentationForActiveTab() {
        guard let activeTab, activeTab.kind == .web,
              let webVM = activeTab.webTabViewModel else {
            isChatPaneVisible = false
            chatViewModel = nil
            return
        }

        syncChatPanePresentation(for: webVM)
    }

    private func syncChatPanePresentation(for webVM: WebTabViewModel) {
        guard let pageURL = webVM.currentURL else {
            isChatPaneVisible = false
            chatViewModel = nil
            return
        }

        let key = pageURL.chatSessionKey
        guard visiblePageChatKeys.contains(key) else {
            isChatPaneVisible = false
            chatViewModel = nil
            return
        }

        activateChatContext(for: webVM)
        isChatPaneVisible = true
    }

    private func activateChatContext(for webVM: WebTabViewModel) {
        guard let pageURL = webVM.currentURL else { return }
        let key = pageURL.chatSessionKey

        let vm: ChatViewModel
        if let existing = pageChatViewModelsByKey[key] {
            vm = existing
        } else {
            vm = makeChatViewModel()
            if !isPrivateBrowsing,
               let snapshot = pageChatSnapshotsByKey[key] {
                vm.restoreConversationHistory(snapshot.conversationHistory)
            }
            vm.primePageContext(url: pageURL, title: webVM.pageTitle)
            pageChatViewModelsByKey[key] = vm
        }

        chatViewModel = vm

        guard vm.pageContent == nil || !isSameChatPage(vm.pageURL, pageURL) else { return }

        Task { @MainActor [weak self, weak vm] in
            guard let self, let vm else { return }
            await vm.updatePageContext(from: webVM)
            self.persistChatSnapshotIfNeeded(from: vm)
        }
    }

    private func makeChatViewModel() -> ChatViewModel {
        let claudeClient = ClaudeAPIClient(getAPIKey: { [apiKeyStore] in apiKeyStore.read(.claudeAPIKey) })
        let vm = ChatViewModel(claudeClient: claudeClient)
        vm.onConversationHistoryChange = { [weak self, weak vm] history in
            guard let self, let vm else { return }
            self.persistChatSnapshotIfNeeded(from: vm, history: history)
        }
        return vm
    }

    private func persistChatSnapshotIfNeeded(
        from chatVM: ChatViewModel,
        history: [ConversationMessage]? = nil
    ) {
        guard !isPrivateBrowsing else { return }
        guard let pageURL = chatVM.pageURL else { return }

        let resolvedHistory = history ?? chatVM.conversationHistory
        let key = pageURL.chatSessionKey
        let isSidebarVisibleForPage = visiblePageChatKeys.contains(key)

        if resolvedHistory.isEmpty && !isSidebarVisibleForPage {
            pageChatSnapshotsByKey.removeValue(forKey: key)
        } else {
            pageChatSnapshotsByKey[key] = PersistedPageChatSnapshot(
                pageURL: pageURL,
                pageTitle: resolvedChatPageTitle(for: chatVM, pageURL: pageURL),
                conversationHistory: resolvedHistory,
                updatedAt: Date(),
                isSidebarVisible: isSidebarVisibleForPage ? true : nil
            )
            trimPageChatSnapshotsIfNeeded()
        }

        persistState()
    }

    private func trimPageChatSnapshotsIfNeeded() {
        guard pageChatSnapshotsByKey.count > maxPersistedPageChats else { return }

        let sorted = pageChatSnapshotsByKey.values.sorted { $0.updatedAt > $1.updatedAt }
        let keysToKeep = Set(sorted.prefix(maxPersistedPageChats).map { $0.pageURL.chatSessionKey })
        pageChatSnapshotsByKey = pageChatSnapshotsByKey.filter { keysToKeep.contains($0.key) }
    }

    private func resolvedChatPageTitle(for chatVM: ChatViewModel, pageURL: URL) -> String {
        let trimmedTitle = chatVM.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        if let persistedTitle = pageChatSnapshotsByKey[pageURL.chatSessionKey]?.pageTitle,
           !persistedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return persistedTitle
        }
        return pageURL.displayHost
    }

    private func isSameChatPage(_ lhs: URL?, _ rhs: URL?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (.some(let left), .some(let right)):
            return left.chatSessionKey == right.chatSessionKey
        default:
            return false
        }
    }

    private func syncWebTabState(_ tab: Tab, from webVM: WebTabViewModel) {
        if webVM.currentURL != nil || tab.url == nil {
            tab.url = webVM.currentURL
        }
        tab.isLoading = webVM.isLoading
        if webVM.faviconURL != nil || webVM.currentURL != nil || tab.url == nil {
            tab.faviconURL = webVM.faviconURL
        }
        tab.pageZoom = persistedPageZoom(for: tab)
        let pageTitle = webVM.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldUseWebTitle =
            !pageTitle.isEmpty &&
            (webVM.currentURL != nil || tab.url == nil || webVM.pageTitle != "New Tab")
        if shouldUseWebTitle {
            tab.title = webVM.pageTitle
        } else if let host = webVM.currentURL?.host {
            tab.title = host
        }
    }

    private func syncIntentBarVisibilityForActiveTab() {
        guard let activeTab else {
            isIntentBarVisible = true
            return
        }

        switch activeTab.kind {
        case .web:
            let offsetY = activeTab.webTabViewModel?.scrollOffsetY ?? 0
            updateIntentBarVisibility(for: offsetY)
        case .briefing:
            isIntentBarFocused = false
            isIntentBarVisible = false
        }
    }

    private func updateIntentBarVisibility(for offsetY: CGFloat) {
        if isFindBarVisibleInActiveTab {
            isIntentBarVisible = true
            return
        }

        if offsetY <= 0 {
            isIntentBarVisible = true
        } else if offsetY > readingScrollHideThreshold {
            guard !isIntentBarFocused else { return }
            guard !isIntentBarRevealZoneHovered else { return }
            guard Date() >= intentBarRevealHoverGraceDeadline else { return }
            isIntentBarVisible = false
        }
    }

    private func shouldHideIntentBarForCurrentContext() -> Bool {
        guard let activeTab else { return false }
        switch activeTab.kind {
        case .web:
            guard activeTab.webTabViewModel?.isFindBarVisible != true else { return false }
            return (activeTab.webTabViewModel?.scrollOffsetY ?? 0) > readingScrollHideThreshold
        case .briefing:
            return (briefingScrollOffsetsByTabID[activeTab.id] ?? 0) > readingScrollHideThreshold
        }
    }

    private func makeBriefingSnapshot(for tab: Tab) -> PersistedBriefingSnapshot? {
        guard tab.kind == .briefing, let briefingVM = tab.briefingViewModel else { return nil }
        return PersistedBriefingSnapshot(
            document: briefingVM.document,
            phase: makePersistedPhase(from: briefingVM.phase),
            conversationHistory: briefingVM.conversationHistory
        )
    }

    private func makePersistedPhase(from phase: BriefingPhase) -> PersistedBriefingPhase {
        switch phase {
        case .idle:
            return .idle
        case .searching, .synthesizing:
            return .error("Briefing was interrupted. Try again.")
        case .complete:
            return .complete
        case .error(let message):
            return .error(message)
        }
    }

    private func makeBriefingPhase(from phase: PersistedBriefingPhase) -> BriefingPhase {
        switch phase {
        case .idle:
            return .idle
        case .searching, .synthesizing:
            return .error("Briefing was interrupted. Try again.")
        case .complete:
            return .complete
        case .error(let message):
            return .error(message)
        }
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.max(min, Swift.min(max, value))
    }
}

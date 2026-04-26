import SwiftUI

@MainActor
@Observable
final class BrowserViewModel {
    private struct RecentlyClosedTab {
        let tab: Tab
        let index: Int
    }

    var tabs: [Tab] = []
    var activeTabID: UUID?
    var isIntentBarFocused: Bool = false
    var isIntentBarVisible: Bool = true
    var isIntentBarRevealZoneHovered: Bool = false
    var isTabBarVisible: Bool = true
    var tabBarWidth: CGFloat = 220
    var isChatPaneVisible: Bool = false
    var chatPaneOffset: CGSize = .zero
    var chatPaneWidth: CGFloat = 380
    var chatPaneHeight: CGFloat = 480
    var chatViewModel: ChatViewModel?

    private let keychain = KeychainService()
    private let persistenceStore = BrowserPersistenceStore()
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
    private let maxRecentlyClosedTabs = 20
    private let maxPersistedPageChats = 120

    var activeTab: Tab? {
        tabs.first { $0.id == activeTabID }
    }

    var shouldShowIntentBar: Bool {
        activeTab?.kind != .briefing && isIntentBarVisible
    }

    init() {
        if !restorePersistedState() {
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
        isIntentBarVisible = true
        isIntentBarFocused = true
        persistState()
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closedTab = tabs[index]
        briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
        rememberClosedTab(closedTab, at: index)

        withAnimation(tabAnimation) {
            tabs.remove(at: index)

            if activeTabID == id {
                if tabs.isEmpty {
                    let tab = makeWebTab(title: "New Tab")
                    tabs.append(tab)
                    activeTabID = tab.id
                    tab.lastAccessedAt = Date()
                    isIntentBarVisible = true
                    isIntentBarFocused = true
                } else {
                    let newIndex = min(index, tabs.count - 1)
                    activeTabID = tabs[newIndex].id
                    tabs[newIndex].lastAccessedAt = Date()
                }
            }
        }
        persistState()
    }

    func closeOtherTabs(keeping id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let closedTabs = tabs.enumerated().filter { $0.element.id != id }
        closedTabs.forEach { originalIndex, closedTab in
            briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
            rememberClosedTab(closedTab, at: originalIndex)
        }

        withAnimation(tabAnimation) {
            tabs.removeAll { $0.id != id }
            activeTabID = id
        }
        tabs.first?.lastAccessedAt = Date()
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func closeTabsBelow(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closeRangeStart = tabs.index(after: index)
        guard closeRangeStart < tabs.endIndex else { return }

        let closedTabs = Array(tabs[closeRangeStart...])
        closedTabs.enumerated().forEach { offset, closedTab in
            briefingScrollOffsetsByTabID.removeValue(forKey: closedTab.id)
            rememberClosedTab(closedTab, at: closeRangeStart + offset)
        }

        withAnimation(tabAnimation) {
            tabs.removeSubrange(closeRangeStart...)
            if activeTabID != nil, !tabs.contains(where: { $0.id == activeTabID }) {
                activeTabID = id
            }
        }
        tabs.first(where: { $0.id == activeTabID })?.lastAccessedAt = Date()
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
                isPinned: sourceTab.isPinned
            )
            if let sourceBriefingVM = sourceTab.briefingViewModel {
                let exaClient = ExaAPIClient(getAPIKey: { [keychain] in keychain.read(.exaAPIKey) })
                let claudeClient = ClaudeAPIClient(getAPIKey: { [keychain] in keychain.read(.claudeAPIKey) })
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
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func reopenLastClosedTab() {
        guard let recentlyClosedTab = recentlyClosedTabs.popLast() else { return }
        let reopenedTab = recentlyClosedTab.tab
        if reopenedTab.kind == .web, let webVM = reopenedTab.webTabViewModel {
            wireWebTabState(for: reopenedTab, webVM: webVM)
            syncWebTabState(reopenedTab, from: webVM)
        }

        let insertionIndex = min(recentlyClosedTab.index, tabs.count)
        withAnimation(tabAnimation) {
            tabs.insert(reopenedTab, at: insertionIndex)
            activeTabID = reopenedTab.id
        }
        reopenedTab.lastAccessedAt = Date()

        if reopenedTab.kind == .web {
            let currentURL = reopenedTab.webTabViewModel?.currentURL ?? reopenedTab.url
            isIntentBarFocused = (currentURL == nil)
        } else {
            isIntentBarFocused = false
        }
        persistState()
    }

    private func rememberClosedTab(_ tab: Tab, at index: Int) {
        recentlyClosedTabs.append(RecentlyClosedTab(tab: tab, index: index))
        if recentlyClosedTabs.count > maxRecentlyClosedTabs {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - maxRecentlyClosedTabs)
        }
    }

    func selectTab(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.16)) {
            activeTabID = id
        }
        if let tab = tabs.first(where: { $0.id == id }) {
            tab.lastAccessedAt = Date()

            // Reset chat pane context when switching tabs
            if isChatPaneVisible {
                if tab.kind == .web, let webVM = tab.webTabViewModel, webVM.currentURL != nil {
                    updateChatContextIfNeeded(for: webVM)
                } else {
                    closeChatPane()
                }
            }
        }
        syncIntentBarVisibilityForActiveTab()
        persistState()
    }

    func selectTabByIndex(_ index: Int) {
        guard index >= 0, index < tabs.count else { return }
        selectTab(tabs[index].id)
    }

    func selectLastTab() {
        guard let lastIndex = tabs.indices.last else { return }
        selectTabByIndex(lastIndex)
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

    func togglePin(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        tab.isPinned.toggle()
        persistState()
    }

    /// Called after a gesture-driven reorder finishes to persist the new tab order.
    func commitTabReorder() {
        persistState()
    }

    func toggleTabBarVisibility() {
        withAnimation(.easeInOut(duration: 0.18)) {
            isTabBarVisible.toggle()
        }
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
              webVM.currentURL != nil else { return }

        updateChatContextIfNeeded(for: webVM)

        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            isChatPaneVisible = true
        }
    }

    func closeChatPane() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) {
            isChatPaneVisible = false
        }
    }

    func clearChatForCurrentPage() {
        guard let chatViewModel, !chatViewModel.isStreaming else { return }
        chatViewModel.clearConversation()
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
        isIntentBarFocused = true
    }

    func reportBriefingScrollOffset(_ offsetY: CGFloat, tabID: UUID) {
        briefingScrollOffsetsByTabID[tabID] = offsetY
        guard activeTabID == tabID else { return }
        guard activeTab?.kind == .briefing else { return }
        isIntentBarFocused = false
        isIntentBarVisible = false
    }

    func hideIntentBarIfReadingPositionActive() {
        guard isIntentBarVisible else { return }
        guard !isIntentBarRevealZoneHovered else { return }
        guard Date() >= intentBarRevealHoverGraceDeadline else { return }
        if shouldHideIntentBarForCurrentContext() {
            isIntentBarVisible = false
        }
    }

    private func openURL(_ url: URL) {
        if let activeTab, activeTab.kind == .web {
            if activeTab.webTabViewModel == nil {
                let vm = WebTabViewModel()
                activeTab.webTabViewModel = vm
                wireWebTabState(for: activeTab, webVM: vm)
            }
            activeTab.webTabViewModel?.navigate(to: url)
            activeTab.url = url
            activeTab.title = url.host ?? url.absoluteString
            activeTab.lastAccessedAt = Date()
        } else {
            let tab = makeWebTab(title: url.host ?? "Loading...", url: url)
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
        let exaClient = ExaAPIClient(getAPIKey: { [keychain] in keychain.read(.exaAPIKey) })
        let claudeClient = ClaudeAPIClient(getAPIKey: { [keychain] in keychain.read(.claudeAPIKey) })
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
            let tab = Tab(kind: .briefing, title: query)
            tab.briefingViewModel = vm
            wireBriefingState(for: tab, briefingVM: vm)
            withAnimation(tabAnimation) {
                tabs.append(tab)
                activeTabID = tab.id
            }
            tab.lastAccessedAt = Date()
        }

        persistState()
        Task {
            await vm.generate()
        }
    }

    private func canReuseAsNewTab(_ tab: Tab) -> Bool {
        guard tab.kind == .web else { return false }
        guard tab.url == nil else { return false }

        guard let webVM = tab.webTabViewModel else { return true }
        return webVM.currentURL == nil
    }

    // MARK: - Source Navigation

    func openSourceInNewTab(_ url: URL) {
        let tab = makeWebTab(title: url.host ?? "Loading...", url: url)
        withAnimation(tabAnimation) {
            tabs.append(tab)
            activeTabID = tab.id
        }
        tab.lastAccessedAt = Date()
        isIntentBarVisible = true
        tab.webTabViewModel?.navigate(to: url)
        persistState()
    }

    // MARK: - Persistence

    private func restorePersistedState() -> Bool {
        guard let persisted = persistenceStore.load() else { return false }
        guard !persisted.tabs.isEmpty else { return false }
        pageChatSnapshotsByKey = [:]
        if let persistedPageChats = persisted.pageChats {
            for snapshot in persistedPageChats {
                let key = snapshot.pageURL.chatSessionKey
                if let existing = pageChatSnapshotsByKey[key],
                   existing.updatedAt > snapshot.updatedAt {
                    continue
                }
                pageChatSnapshotsByKey[key] = snapshot
            }
        }

        tabs = persisted.tabs.map { snapshot in
            let tab = Tab(
                id: snapshot.id,
                kind: snapshot.kind,
                title: snapshot.title,
                url: snapshot.url,
                isPinned: snapshot.isPinned,
                createdAt: snapshot.createdAt,
                lastAccessedAt: snapshot.lastAccessedAt
            )

            if tab.kind == .web {
                let webVM = WebTabViewModel()
                tab.webTabViewModel = webVM
                wireWebTabState(for: tab, webVM: webVM)
                if let url = tab.url {
                    webVM.navigate(to: url)
                }
            } else if tab.kind == .briefing {
                let exaClient = ExaAPIClient(getAPIKey: { [keychain] in keychain.read(.exaAPIKey) })
                let claudeClient = ClaudeAPIClient(getAPIKey: { [keychain] in keychain.read(.claudeAPIKey) })
                let briefingVM = BriefingViewModel(
                    query: snapshot.briefing?.document.query ?? snapshot.title,
                    exaClient: exaClient,
                    claudeClient: claudeClient
                )

                if let briefingSnapshot = snapshot.briefing {
                    briefingVM.document = briefingSnapshot.document
                    briefingVM.phase = makeBriefingPhase(from: briefingSnapshot.phase)
                    briefingVM.conversationHistory = briefingSnapshot.conversationHistory
                }

                tab.briefingViewModel = briefingVM
                wireBriefingState(for: tab, briefingVM: briefingVM)
            }

            return tab
        }

        activeTabID = persisted.activeTabID.flatMap { id in
            tabs.contains(where: { $0.id == id }) ? id : nil
        } ?? tabs.first?.id

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
        return true
    }

    private func makePersistedState() -> PersistedBrowserState {
        let tabSnapshots = tabs.map { tab in
            PersistedTabSnapshot(
                id: tab.id,
                kind: tab.kind,
                title: tab.title,
                url: tab.url,
                isPinned: tab.isPinned,
                createdAt: tab.createdAt,
                lastAccessedAt: tab.lastAccessedAt,
                briefing: makeBriefingSnapshot(for: tab)
            )
        }
        return PersistedBrowserState(
            tabs: tabSnapshots,
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
        persistenceStore.save(makePersistedState())
    }

    private func makePersistedPageChatSnapshots() -> [PersistedPageChatSnapshot]? {
        var snapshotsByKey = pageChatSnapshotsByKey

        // Ensure the in-memory active chat is not dropped if it changed very recently.
        if let chatVM = chatViewModel,
           let pageURL = chatVM.pageURL,
           !chatVM.conversationHistory.isEmpty {
            let title = resolvedChatPageTitle(for: chatVM, pageURL: pageURL)
            snapshotsByKey[pageURL.chatSessionKey] = PersistedPageChatSnapshot(
                pageURL: pageURL,
                pageTitle: title,
                conversationHistory: chatVM.conversationHistory,
                updatedAt: Date()
            )
        }

        let snapshots = snapshotsByKey.values
            .filter { !$0.conversationHistory.isEmpty }
            .sorted { $0.updatedAt > $1.updatedAt }

        guard !snapshots.isEmpty else { return nil }
        return Array(snapshots.prefix(maxPersistedPageChats))
    }

    private func makeWebTab(
        title: String,
        url: URL? = nil,
        id: UUID = UUID(),
        isPinned: Bool = false,
        createdAt: Date = Date(),
        lastAccessedAt: Date = Date()
    ) -> Tab {
        let tab = Tab(
            id: id,
            kind: .web,
            title: title,
            url: url,
            isPinned: isPinned,
            createdAt: createdAt,
            lastAccessedAt: lastAccessedAt
        )
        let webVM = WebTabViewModel()
        tab.webTabViewModel = webVM
        wireWebTabState(for: tab, webVM: webVM)
        return tab
    }

    private func wireWebTabState(for tab: Tab, webVM: WebTabViewModel) {
        webVM.onStateChange = { [weak self, weak tab, weak webVM] in
            guard let self, let tab, let webVM else { return }
            self.syncWebTabState(tab, from: webVM)
            self.persistState()

            // Keep chat pane tied to the current page URL for the active tab.
            if tab.id == self.activeTabID,
               self.isChatPaneVisible,
               webVM.currentURL != nil {
                self.updateChatContextIfNeeded(for: webVM)
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

    private func updateChatContextIfNeeded(for webVM: WebTabViewModel) {
        guard let pageURL = webVM.currentURL else { return }

        if let existingChatVM = chatViewModel,
           isSameChatPage(existingChatVM.pageURL, pageURL) {
            return
        }

        let vm = makeChatViewModel()
        if let snapshot = pageChatSnapshotsByKey[pageURL.chatSessionKey] {
            vm.restoreConversationHistory(snapshot.conversationHistory)
        }
        vm.primePageContext(url: pageURL, title: webVM.pageTitle)
        chatViewModel = vm

        Task { @MainActor [weak self, weak vm] in
            guard let self, let vm else { return }
            await vm.updatePageContext(from: webVM)
            self.persistChatSnapshotIfNeeded(from: vm)
        }
    }

    private func makeChatViewModel() -> ChatViewModel {
        let claudeClient = ClaudeAPIClient(getAPIKey: { [keychain] in keychain.read(.claudeAPIKey) })
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
        guard let pageURL = chatVM.pageURL else { return }

        let resolvedHistory = history ?? chatVM.conversationHistory
        let key = pageURL.chatSessionKey

        if resolvedHistory.isEmpty {
            pageChatSnapshotsByKey.removeValue(forKey: key)
        } else {
            pageChatSnapshotsByKey[key] = PersistedPageChatSnapshot(
                pageURL: pageURL,
                pageTitle: resolvedChatPageTitle(for: chatVM, pageURL: pageURL),
                conversationHistory: resolvedHistory,
                updatedAt: Date()
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
        tab.url = webVM.currentURL
        tab.isLoading = webVM.isLoading
        tab.faviconURL = webVM.faviconURL
        if !webVM.pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        case .searching:
            return .searching
        case .synthesizing:
            return .synthesizing
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
        case .searching:
            return .searching
        case .synthesizing:
            return .synthesizing
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

import SwiftUI

// MARK: - Session Persistence

extension ContentView {
    // MARK: - Startup Restore

    func applyStartupBehaviorIfNeeded() {
        guard !didApplyStartupBehavior else { return }

        if startupBehavior == .forceBlankDocument || startupBehavior == .safeMode {
            viewModel.resetTabsForSessionRestore()
            viewModel.addNewTab()
            projectRootFolderURL = nil
            clearProjectEditorOverrides()
            projectTreeNodes = []
            quickSwitcherProjectFileURLs = []
            stopProjectFolderObservation()
            projectFileIndexSnapshot = .empty
            isProjectFileIndexing = false
            projectFileIndexTask?.cancel()
            projectFileIndexTask = nil
            didApplyStartupBehavior = true
            if startupBehavior != .safeMode {
                persistSessionIfReady()
            }
            return
        }

        if viewModel.tabs.contains(where: { $0.fileURL != nil }) {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        // If both startup toggles are enabled (legacy/default mismatch), prefer session restore.
        let shouldOpenBlankOnStartup = openWithBlankDocument && !reopenLastSession
        if shouldOpenBlankOnStartup {
            viewModel.resetTabsForSessionRestore()
            viewModel.addNewTab()
            projectRootFolderURL = nil
            clearProjectEditorOverrides()
            projectTreeNodes = []
            quickSwitcherProjectFileURLs = []
            stopProjectFolderObservation()
            projectFileIndexSnapshot = .empty
            isProjectFileIndexing = false
            projectFileIndexTask?.cancel()
            projectFileIndexTask = nil
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

        var restoredSessionTabs = false

        // Restore last session first when enabled.
        if reopenLastSession {
            if projectRootFolderURL == nil, let restoredProjectFolderURL = restoredLastSessionProjectFolderURL() {
                setProjectFolder(restoredProjectFolderURL)
            }
            let urls = restoredLastSessionFileURLs()
            let selectedURL = restoredLastSessionSelectedFileURL()

            if !urls.isEmpty {
                viewModel.resetTabsForSessionRestore()

                for url in urls {
                    viewModel.openFile(url: url)
                }

                if let selectedURL {
                    _ = viewModel.focusTabIfOpen(for: selectedURL)
                }

                restoredSessionTabs = !viewModel.tabs.isEmpty
                if viewModel.tabs.isEmpty {
                    viewModel.addNewTab()
                }
            }
        }

        // Restore unsaved drafts only as fallback when no file session tabs were restored.
        if !restoredSessionTabs, restoreUnsavedDraftSnapshotIfAvailable() {
            didApplyStartupBehavior = true
            persistSessionIfReady()
            return
        }

#if os(iOS)
        // Keep mobile layout in a valid tab state so the file tab bar always has content.
        if viewModel.tabs.isEmpty {
            viewModel.addNewTab()
        }
#endif

        restoreLastSessionViewContextIfAvailable()
        restoreCaretForSelectedSessionFileIfAvailable()
        didApplyStartupBehavior = true
        persistSessionIfReady()
    }

    // MARK: - Last Session Files

    func persistSessionIfReady() {
        guard didApplyStartupBehavior else { return }
        guard startupBehavior != .safeMode else { return }
        let fileURLs = viewModel.tabs.compactMap { $0.fileURL }
        UserDefaults.standard.set(fileURLs.map(\.absoluteString), forKey: "LastSessionFileURLs")
        UserDefaults.standard.set(viewModel.selectedTab?.fileURL?.absoluteString, forKey: "LastSessionSelectedFileURL")
        persistLastSessionViewContext()
        persistLastSessionProjectFolderURL(projectRootFolderURL)
#if os(iOS)
        persistLastSessionSecurityScopedBookmarks(fileURLs: fileURLs, selectedURL: viewModel.selectedTab?.fileURL)
#elseif os(macOS)
        persistLastSessionSecurityScopedBookmarksMac(fileURLs: fileURLs, selectedURL: viewModel.selectedTab?.fileURL)
#endif
    }

    func restoredLastSessionFileURLs() -> [URL] {
#if os(macOS)
        let bookmarked = restoreSessionURLsFromSecurityScopedBookmarksMac()
        if !bookmarked.isEmpty {
            return bookmarked
        }
#elseif os(iOS)
        let bookmarked = restoreSessionURLsFromSecurityScopedBookmarks()
        if !bookmarked.isEmpty {
            return bookmarked
        }
#endif
        let stored = UserDefaults.standard.stringArray(forKey: "LastSessionFileURLs") ?? []
        var urls: [URL] = []
        var seen: Set<String> = []
        for raw in stored {
            guard let parsed = restoredSessionURL(from: raw) else { continue }
            let standardized = parsed.standardizedFileURL
            // Only restore files that still exist; avoids empty placeholder tabs on launch.
            guard FileManager.default.fileExists(atPath: standardized.path) else { continue }
            let key = standardized.absoluteString
            if seen.insert(key).inserted {
                urls.append(standardized)
            }
        }
        return urls
    }

    func restoredLastSessionSelectedFileURL() -> URL? {
#if os(macOS)
        if let bookmarked = restoreSelectedURLFromSecurityScopedBookmarkMac() {
            return bookmarked
        }
#elseif os(iOS)
        if let bookmarked = restoreSelectedURLFromSecurityScopedBookmark() {
            return bookmarked
        }
#endif
        guard let selectedPath = UserDefaults.standard.string(forKey: "LastSessionSelectedFileURL"),
              let selectedURL = restoredSessionURL(from: selectedPath) else {
            return nil
        }
        let standardized = selectedURL.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    func restoredSessionURL(from raw: String) -> URL? {
        // Support both absolute URL strings ("file:///...") and legacy plain paths.
        if let url = URL(string: raw), url.isFileURL {
            return url
        }
        if raw.hasPrefix("/") {
            return URL(fileURLWithPath: raw)
        }
        return nil
    }

    var lastSessionShowSidebarKey: String { "LastSessionShowSidebarV1" }
    var lastSessionShowProjectSidebarKey: String { "LastSessionShowProjectSidebarV1" }
    var lastSessionShowMarkdownPreviewKey: String { "LastSessionShowMarkdownPreviewV1" }
    var lastSessionCaretByFileURLKey: String { "LastSessionCaretByFileURLV1" }

    var lastSessionProjectFolderURLKey: String { "LastSessionProjectFolderURL" }

    // MARK: - Last Session View Context

    func persistLastSessionViewContext() {
        let defaults = UserDefaults.standard
        defaults.set(viewModel.showSidebar, forKey: lastSessionShowSidebarKey)
        defaults.set(showProjectStructureSidebar, forKey: lastSessionShowProjectSidebarKey)
        defaults.set(showMarkdownPreviewPane, forKey: lastSessionShowMarkdownPreviewKey)

        if let selectedURL = viewModel.selectedTab?.fileURL {
            let key = selectedURL.standardizedFileURL.absoluteString
            if !key.isEmpty {
                sessionCaretByFileURL[key] = max(0, lastCaretLocation)
            }
        }
        defaults.set(sessionCaretByFileURL, forKey: lastSessionCaretByFileURLKey)
    }

    func restoreLastSessionViewContextIfAvailable() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: lastSessionShowSidebarKey) != nil {
            viewModel.showSidebar = defaults.bool(forKey: lastSessionShowSidebarKey)
        }
        if defaults.object(forKey: lastSessionShowProjectSidebarKey) != nil {
            showProjectStructureSidebar = defaults.bool(forKey: lastSessionShowProjectSidebarKey)
        }
        if defaults.object(forKey: lastSessionShowMarkdownPreviewKey) != nil {
            showMarkdownPreviewPane = defaults.bool(forKey: lastSessionShowMarkdownPreviewKey)
        }
        sessionCaretByFileURL = defaults.dictionary(forKey: lastSessionCaretByFileURLKey) as? [String: Int] ?? [:]
    }

    func restoreCaretForSelectedSessionFileIfAvailable() {
        guard let selectedURL = viewModel.selectedTab?.fileURL?.standardizedFileURL else { return }
        guard let location = sessionCaretByFileURL[selectedURL.absoluteString], location >= 0 else { return }
        var userInfo: [String: Any] = [
            EditorCommandUserInfo.rangeLocation: location,
            EditorCommandUserInfo.rangeLength: 0,
            EditorCommandUserInfo.focusEditor: true
        ]
#if os(macOS)
        if let hostWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = hostWindowNumber
        }
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: userInfo)
        }
    }

    func persistLastSessionProjectFolderURL(_ folderURL: URL?) {
        guard let folderURL else {
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderURLKey)
#if os(macOS)
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
#elseif os(iOS)
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderBookmarkKey)
#endif
            return
        }

        UserDefaults.standard.set(folderURL.absoluteString, forKey: lastSessionProjectFolderURLKey)
#if os(macOS)
        if let bookmark = makeSecurityScopedBookmarkDataMac(for: folderURL) {
            UserDefaults.standard.set(bookmark, forKey: macLastSessionProjectFolderBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
        }
#elseif os(iOS)
        if let bookmark = makeSecurityScopedBookmarkData(for: folderURL) {
            UserDefaults.standard.set(bookmark, forKey: lastSessionProjectFolderBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderBookmarkKey)
        }
#endif
    }

    func restoredLastSessionProjectFolderURL() -> URL? {
#if os(macOS)
        if let bookmarked = restoreProjectFolderURLFromSecurityScopedBookmarkMac() {
            return bookmarked
        }
#elseif os(iOS)
        if let bookmarked = restoreProjectFolderURLFromSecurityScopedBookmark() {
            return bookmarked
        }
#endif
        guard let raw = UserDefaults.standard.string(forKey: lastSessionProjectFolderURLKey),
              let parsed = restoredSessionURL(from: raw) else {
            return nil
        }
        let standardized = parsed.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

#if os(macOS)
    // MARK: - macOS Security-Scoped Bookmarks

    var macLastSessionBookmarksKey: String { "MacLastSessionFileBookmarks" }
    var macLastSessionSelectedBookmarkKey: String { "MacLastSessionSelectedFileBookmark" }
    var macLastSessionProjectFolderBookmarkKey: String { "MacLastSessionProjectFolderBookmark" }

    func persistLastSessionSecurityScopedBookmarksMac(fileURLs: [URL], selectedURL: URL?) {
        let bookmarkData = fileURLs.compactMap { makeSecurityScopedBookmarkDataMac(for: $0) }
        UserDefaults.standard.set(bookmarkData, forKey: macLastSessionBookmarksKey)
        if let selectedURL, let selectedData = makeSecurityScopedBookmarkDataMac(for: selectedURL) {
            UserDefaults.standard.set(selectedData, forKey: macLastSessionSelectedBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: macLastSessionSelectedBookmarkKey)
        }
    }

    func restoreSessionURLsFromSecurityScopedBookmarksMac() -> [URL] {
        guard let saved = UserDefaults.standard.array(forKey: macLastSessionBookmarksKey) as? [Data], !saved.isEmpty else {
            return []
        }
        var urls: [URL] = []
        var seen: Set<String> = []
        for data in saved {
            guard let url = resolveSecurityScopedBookmarkMac(data) else { continue }
            let standardized = url.standardizedFileURL
            guard fileExistsWithScopedAccessMac(standardized) else { continue }
            let key = standardized.absoluteString
            if seen.insert(key).inserted {
                urls.append(standardized)
            }
        }
        return urls
    }

    func restoreSelectedURLFromSecurityScopedBookmarkMac() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: macLastSessionSelectedBookmarkKey),
              let resolved = resolveSecurityScopedBookmarkMac(data) else {
            return nil
        }
        let standardized = resolved.standardizedFileURL
        return fileExistsWithScopedAccessMac(standardized) ? standardized : nil
    }

    func restoreProjectFolderURLFromSecurityScopedBookmarkMac() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: macLastSessionProjectFolderBookmarkKey),
              let resolved = resolveSecurityScopedBookmarkMac(data) else {
            return nil
        }
        let standardized = resolved.standardizedFileURL
        return fileExistsWithScopedAccessMac(standardized) ? standardized : nil
    }

    func makeSecurityScopedBookmarkDataMac(for url: URL) -> Data? {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    func resolveSecurityScopedBookmarkMac(_ data: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return resolved
    }

    private func fileExistsWithScopedAccessMac(_ url: URL) -> Bool {
        let didStartScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
#endif

    // MARK: - Unsaved Draft Recovery

    var unsavedDraftSnapshotRegistryKey: String { "UnsavedDraftSnapshotRegistryV1" }
    var unsavedDraftSnapshotKey: String { "UnsavedDraftSnapshotV2.\(recoverySnapshotIdentifier)" }
    var maxPersistedDraftTabs: Int { 20 }
    var maxPersistedDraftUTF16Length: Int { 2_000_000 }

    func persistUnsavedDraftSnapshotIfNeeded() {
        let defaults = UserDefaults.standard
        let dirtyTabs = viewModel.tabs.filter(\.isDirty)
        var registry = defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? []

        guard !dirtyTabs.isEmpty else {
            defaults.removeObject(forKey: unsavedDraftSnapshotKey)
            registry.removeAll { $0 == unsavedDraftSnapshotKey }
            defaults.set(registry, forKey: unsavedDraftSnapshotRegistryKey)
            return
        }

        var savedTabs: [SavedDraftTabSnapshot] = []
        savedTabs.reserveCapacity(min(dirtyTabs.count, maxPersistedDraftTabs))
        for tab in dirtyTabs.prefix(maxPersistedDraftTabs) {
            let content = tab.content
            let nsContent = content as NSString
            let clampedContent = nsContent.length > maxPersistedDraftUTF16Length
                ? nsContent.substring(to: maxPersistedDraftUTF16Length)
                : content
            savedTabs.append(
                SavedDraftTabSnapshot(
                    name: tab.name,
                    content: clampedContent,
                    language: tab.language,
                    fileURLString: tab.fileURL?.absoluteString
                )
            )
        }

        let selectedIndex: Int? = {
            guard let selectedID = viewModel.selectedTabID else { return nil }
            return dirtyTabs.firstIndex(where: { $0.id == selectedID })
        }()

        let snapshot = SavedDraftSnapshot(tabs: savedTabs, selectedIndex: selectedIndex, createdAt: Date())
        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(encoded, forKey: unsavedDraftSnapshotKey)
        if !registry.contains(unsavedDraftSnapshotKey) {
            registry.append(unsavedDraftSnapshotKey)
            defaults.set(registry, forKey: unsavedDraftSnapshotRegistryKey)
        }
    }

    func restoreUnsavedDraftSnapshotIfAvailable() -> Bool {
        let defaults = UserDefaults.standard
        let keys = defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? []
        guard !keys.isEmpty else { return false }

        var snapshots: [SavedDraftSnapshot] = []
        for key in keys {
            guard let data = defaults.data(forKey: key),
                  let snapshot = try? JSONDecoder().decode(SavedDraftSnapshot.self, from: data),
                  !snapshot.tabs.isEmpty else {
                continue
            }
            snapshots.append(snapshot)
        }
        guard !snapshots.isEmpty else { return false }

        snapshots.sort { $0.createdAt < $1.createdAt }
        let mergedTabs = snapshots.flatMap(\.tabs)
        guard !mergedTabs.isEmpty else { return false }

        let restoredTabs = mergedTabs.map { saved in
            EditorViewModel.RestoredTabSnapshot(
                name: saved.name,
                content: saved.content,
                language: saved.language,
                fileURL: saved.fileURLString.flatMap(URL.init(string:)),
                languageLocked: true,
                isDirty: true,
                lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil
            )
        }
        viewModel.restoreTabsFromSnapshot(restoredTabs, selectedIndex: nil)

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: unsavedDraftSnapshotRegistryKey)
        return true
    }

#if os(iOS)
    // MARK: - iOS Security-Scoped Bookmarks

    var lastSessionBookmarksKey: String { "LastSessionFileBookmarks" }
    var lastSessionSelectedBookmarkKey: String { "LastSessionSelectedFileBookmark" }
    var lastSessionProjectFolderBookmarkKey: String { "LastSessionProjectFolderBookmark" }

    func persistLastSessionSecurityScopedBookmarks(fileURLs: [URL], selectedURL: URL?) {
        let bookmarkData = fileURLs.compactMap { makeSecurityScopedBookmarkData(for: $0) }
        UserDefaults.standard.set(bookmarkData, forKey: lastSessionBookmarksKey)
        if let selectedURL, let selectedData = makeSecurityScopedBookmarkData(for: selectedURL) {
            UserDefaults.standard.set(selectedData, forKey: lastSessionSelectedBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: lastSessionSelectedBookmarkKey)
        }
    }

    func restoreSessionURLsFromSecurityScopedBookmarks() -> [URL] {
        guard let saved = UserDefaults.standard.array(forKey: lastSessionBookmarksKey) as? [Data], !saved.isEmpty else {
            return []
        }
        var urls: [URL] = []
        var seen: Set<String> = []
        for data in saved {
            guard let url = resolveSecurityScopedBookmark(data) else { continue }
            let key = url.standardizedFileURL.absoluteString
            if seen.insert(key).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    func restoreSelectedURLFromSecurityScopedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionSelectedBookmarkKey) else { return nil }
        return resolveSecurityScopedBookmark(data)
    }

    func restoreProjectFolderURLFromSecurityScopedBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionProjectFolderBookmarkKey),
              let resolved = resolveSecurityScopedBookmark(data) else { return nil }
        let standardized = resolved.standardizedFileURL
        return FileManager.default.fileExists(atPath: standardized.path) ? standardized : nil
    }

    func makeSecurityScopedBookmarkData(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return resolved
    }
#endif
}

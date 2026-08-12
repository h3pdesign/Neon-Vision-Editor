import CryptoKit
import SwiftUI

struct DraftSnapshotTabIdentity: Hashable {
    let name: String
    let contentDigest: Data
    let language: String
    let fileURLString: String?

    init(tab: ContentView.SavedDraftTabSnapshot) {
        name = tab.name
        contentDigest = Data(SHA256.hash(data: Data(tab.content.utf8)))
        language = tab.language
        fileURLString = tab.fileURLString
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        if let lhsFileURL = lhs.fileURLString, let rhsFileURL = rhs.fileURLString {
            return lhsFileURL == rhsFileURL
        }
        return lhs.fileURLString == nil
            && rhs.fileURLString == nil
            && lhs.name == rhs.name
            && lhs.contentDigest == rhs.contentDigest
            && lhs.language == rhs.language
    }

    func hash(into hasher: inout Hasher) {
        if let fileURLString {
            hasher.combine(0)
            hasher.combine(fileURLString)
        } else {
            hasher.combine(1)
            hasher.combine(name)
            hasher.combine(contentDigest)
            hasher.combine(language)
        }
    }
}

func deduplicatedDraftSnapshotTabs(
    _ tabs: [ContentView.SavedDraftTabSnapshot]
) -> [ContentView.SavedDraftTabSnapshot] {
    var seen = Set<DraftSnapshotTabIdentity>()
    var result: [ContentView.SavedDraftTabSnapshot] = []

    for tab in tabs {
        let identity = DraftSnapshotTabIdentity(tab: tab)
        if seen.insert(identity).inserted {
            result.append(tab)
        }
    }
    return result
}

func restoredDraftSnapshotSelectionIndex(
    snapshot: ContentView.SavedDraftSnapshot,
    mergedTabs: [ContentView.SavedDraftTabSnapshot]
) -> Int? {
    guard let selectedIndex = snapshot.selectedIndex,
          snapshot.tabs.indices.contains(selectedIndex) else {
        return nil
    }
    let selectedIdentity = DraftSnapshotTabIdentity(tab: snapshot.tabs[selectedIndex])
    return mergedTabs.firstIndex { DraftSnapshotTabIdentity(tab: $0) == selectedIdentity }
}

func restoredDraftSnapshotState(
    from snapshots: [ContentView.SavedDraftSnapshot]
) -> (tabs: [ContentView.SavedDraftTabSnapshot], selectedIndex: Int?)? {
    let newestFirst = snapshots.sorted { $0.createdAt > $1.createdAt }
    guard let newestSnapshot = newestFirst.first else { return nil }
    let mergedTabs = deduplicatedDraftSnapshotTabs(newestFirst.flatMap(\.tabs))
    guard !mergedTabs.isEmpty else { return nil }
    return (
        tabs: mergedTabs,
        selectedIndex: restoredDraftSnapshotSelectionIndex(
            snapshot: newestSnapshot,
            mergedTabs: mergedTabs
        )
    )
}

// MARK: - Session Persistence

extension ContentView {
    // MARK: - Startup Restore

    func applyStartupBehaviorIfNeeded() {
        guard !didApplyStartupBehavior else { return }

        if startupBehavior == .forceBlankDocument || startupBehavior == .safeMode {
            resetForBlankStartup()
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
            resetForBlankStartup()
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
            let encodingPreferences = restoredLastSessionEncodingPreferences()

            if !urls.isEmpty {
                viewModel.resetTabsForSessionRestore()

                for url in urls {
                    let preference = encodingPreferences[url.standardizedFileURL.absoluteString]
                    viewModel.openFile(
                        url: url,
                        preferredEncoding: preference?.encoding,
                        usesAutomaticEncoding: preference?.usesAutomatic ?? true
                    )
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
        if recoverUnsavedDrafts, !restoredSessionTabs, restoreUnsavedDraftSnapshotIfAvailable() {
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
        didApplyStartupBehavior = true
        persistSessionIfReady()
    }

    private func resetForBlankStartup() {
        viewModel.resetTabsForSessionRestore()
        viewModel.addNewTab()
        projectRootFolderURL = nil
        clearProjectEditorOverrides()
        projectTreeNodes = []
        quickSwitcherProjectFileURLs = []
        stopProjectFolderObservation()
        projectFileIndexSnapshot = .empty
        isProjectFileIndexing = false
        projectFileIndexHasCompleted = false
        projectFileIndexTask?.cancel()
        projectFileIndexTask = nil
    }

    // MARK: - Last Session Files

    func scheduleSessionPersistence(delay: TimeInterval = 0.5) {
        pendingSessionPersistenceWorkItem?.cancel()
        let work = DispatchWorkItem {
            pendingSessionPersistenceWorkItem = nil
            persistSessionIfReady()
        }
        pendingSessionPersistenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Keep the selected document available for the next launch without doing
    /// bookmark generation while the user is changing tabs. Creating
    /// security-scoped bookmarks walks every open URL and is deliberately left
    /// to the debounced persistence pass (and the app/window lifecycle hooks).
    func persistSelectedSessionFileURLImmediately() {
        guard didApplyStartupBehavior, startupBehavior != .safeMode else { return }
        if let selectedURL = viewModel.selectedTab?.fileURL?.absoluteString {
            UserDefaults.standard.set(selectedURL, forKey: "LastSessionSelectedFileURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "LastSessionSelectedFileURL")
        }
    }

    func scheduleUnsavedDraftSnapshotPersistence(delay: TimeInterval = 0.7) {
        guard recoverUnsavedDrafts else {
            clearUnsavedDraftSnapshots()
            return
        }
        pendingDraftSnapshotPersistenceWorkItem?.cancel()
        let work = DispatchWorkItem {
            pendingDraftSnapshotPersistenceWorkItem = nil
            persistUnsavedDraftSnapshotIfNeeded()
        }
        pendingDraftSnapshotPersistenceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func persistSessionIfReady() {
        guard didApplyStartupBehavior else { return }
        guard startupBehavior != .safeMode else { return }
        let fileURLs = viewModel.tabs.compactMap { $0.fileURL }
        let selectedURL = viewModel.selectedTab?.fileURL
        let signature = ([
            fileURLs.map(\.absoluteString).joined(separator: "|"),
            selectedURL?.absoluteString ?? "",
            viewModel.showSidebar.description,
            showProjectStructureSidebar.description,
            previewMode.rawValue,
            projectRootFolderURL?.absoluteString ?? "",
            sessionCaretByFileURL
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "|"),
            viewModel.tabs.compactMap { tab in
                guard let url = tab.fileURL else { return nil }
                return "\(url.standardizedFileURL.absoluteString)=\(tab.fileEncoding.identifier.rawValue):\(tab.usesAutomaticFileEncoding)"
            }.joined(separator: "|")
        ]).joined(separator: "\n")
        guard signature != lastPersistedSessionSignature else { return }
        lastPersistedSessionSignature = signature
        UserDefaults.standard.set(fileURLs.map(\.absoluteString), forKey: "LastSessionFileURLs")
        UserDefaults.standard.set(viewModel.selectedTab?.fileURL?.absoluteString, forKey: "LastSessionSelectedFileURL")
        persistLastSessionEncodingPreferences()
        persistLastSessionViewContext()
        persistLastSessionProjectFolderReference(projectRootFolderURL)

        let bookmarkSignature = ([
            fileURLs.map { $0.standardizedFileURL.absoluteString }.joined(separator: "|"),
            selectedURL?.standardizedFileURL.absoluteString ?? "",
            projectRootFolderURL?.standardizedFileURL.absoluteString ?? ""
        ]).joined(separator: "\n")
        guard bookmarkSignature != lastPersistedSessionBookmarkSignature else { return }
        lastPersistedSessionBookmarkSignature = bookmarkSignature
        persistLastSessionProjectFolderSecurityScopedBookmark(projectRootFolderURL)
#if os(iOS) || os(visionOS)
        persistLastSessionSecurityScopedBookmarks(fileURLs: fileURLs, selectedURL: selectedURL)
#elseif os(macOS)
        persistLastSessionSecurityScopedBookmarksMac(fileURLs: fileURLs, selectedURL: selectedURL)
#endif
    }

    func restoredLastSessionFileURLs() -> [URL] {
#if os(macOS)
        let bookmarked = restoreSessionURLsFromSecurityScopedBookmarksMac()
        if !bookmarked.isEmpty {
            return bookmarked
        }
#elseif os(iOS) || os(visionOS)
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
#elseif os(iOS) || os(visionOS)
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
    var lastSessionPreviewModeKey: String { "LastSessionPreviewModeV1" }
    var lastSessionCaretByFileURLKey: String { "LastSessionCaretByFileURLV1" }
    var lastSessionEncodingByFileURLKey: String { "LastSessionEncodingByFileURLV2" }
    var lastSessionAutomaticEncodingByFileURLKey: String { "LastSessionAutomaticEncodingByFileURLV2" }

    var lastSessionProjectFolderURLKey: String { "LastSessionProjectFolderURL" }

    struct RestoredEncodingPreference {
        let encoding: TextEncodingDescriptor
        let usesAutomatic: Bool
    }

    func persistLastSessionEncodingPreferences() {
        var identifiers: [String: String] = [:]
        var automaticModes: [String: Bool] = [:]
        for tab in viewModel.tabs {
            guard let url = tab.fileURL else { continue }
            let key = url.standardizedFileURL.absoluteString
            identifiers[key] = tab.fileEncoding.identifier.rawValue
            automaticModes[key] = tab.usesAutomaticFileEncoding
        }
        UserDefaults.standard.set(identifiers, forKey: lastSessionEncodingByFileURLKey)
        UserDefaults.standard.set(automaticModes, forKey: lastSessionAutomaticEncodingByFileURLKey)
    }

    func restoredLastSessionEncodingPreferences() -> [String: RestoredEncodingPreference] {
        let defaults = UserDefaults.standard
        let identifiers = defaults.dictionary(forKey: lastSessionEncodingByFileURLKey) as? [String: String] ?? [:]
        let automaticModes = defaults.dictionary(forKey: lastSessionAutomaticEncodingByFileURLKey) as? [String: Bool] ?? [:]
        return identifiers.reduce(into: [:]) { result, pair in
            guard let identifier = TextEncodingDescriptor.Identifier(rawValue: pair.value) else { return }
            result[pair.key] = RestoredEncodingPreference(
                encoding: TextEncodingDescriptor(identifier: identifier),
                usesAutomatic: automaticModes[pair.key] ?? true
            )
        }
    }

    // MARK: - Last Session View Context

    func persistLastSessionViewContext() {
        let defaults = UserDefaults.standard
        defaults.set(viewModel.showSidebar, forKey: lastSessionShowSidebarKey)
        defaults.set(showProjectStructureSidebar, forKey: lastSessionShowProjectSidebarKey)
        defaults.set(previewMode.rawValue, forKey: lastSessionPreviewModeKey)

        if let selectedURL = viewModel.selectedTab?.fileURL {
            let key = selectedURL.standardizedFileURL.absoluteString
            if !key.isEmpty, sessionCaretByFileURL[key] == nil {
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
        if let rawPreviewMode = defaults.string(forKey: lastSessionPreviewModeKey),
           let restoredPreviewMode = PreviewMode(rawValue: rawPreviewMode) {
            previewMode = restoredPreviewMode
        } else if defaults.object(forKey: lastSessionShowMarkdownPreviewKey) != nil {
            showMarkdownPreviewPane = defaults.bool(forKey: lastSessionShowMarkdownPreviewKey)
        }
        sessionCaretByFileURL = defaults.dictionary(forKey: lastSessionCaretByFileURLKey) as? [String: Int] ?? [:]
    }

    func persistLastSessionProjectFolderReference(_ folderURL: URL?) {
        guard let folderURL else {
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderURLKey)
            return
        }
        UserDefaults.standard.set(folderURL.absoluteString, forKey: lastSessionProjectFolderURLKey)
    }

    func persistLastSessionProjectFolderSecurityScopedBookmark(_ folderURL: URL?) {
        guard let folderURL else {
#if os(macOS)
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
#elseif os(iOS) || os(visionOS)
            UserDefaults.standard.removeObject(forKey: lastSessionProjectFolderBookmarkKey)
#endif
            return
        }

#if os(macOS)
        if let bookmark = makeSecurityScopedBookmarkDataMac(for: folderURL) {
            UserDefaults.standard.set(bookmark, forKey: macLastSessionProjectFolderBookmarkKey)
        } else {
            UserDefaults.standard.removeObject(forKey: macLastSessionProjectFolderBookmarkKey)
        }
#elseif os(iOS) || os(visionOS)
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
#elseif os(iOS) || os(visionOS)
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
    var maxPersistedDraftUTF16Length: Int { 1_000_000 }
    var maxPersistedDraftTotalUTF16Length: Int { 4_000_000 }

    func persistUnsavedDraftSnapshotIfNeeded() {
        guard recoverUnsavedDrafts else {
            clearUnsavedDraftSnapshots()
            return
        }
        let defaults = UserDefaults.standard
        let dirtyTabs = viewModel.tabs.filter(\.isDirty)
        let signature = dirtyTabs.isEmpty
            ? "clean"
            : dirtyTabs.map { "\($0.id.uuidString):\($0.contentRevision)" }.joined(separator: "|")
        guard signature != lastPersistedDraftSignature else { return }
        lastPersistedDraftSignature = signature
        var registry = defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? []

        guard !dirtyTabs.isEmpty else {
            defaults.removeObject(forKey: unsavedDraftSnapshotKey)
            registry.removeAll { $0 == unsavedDraftSnapshotKey }
            defaults.set(registry, forKey: unsavedDraftSnapshotRegistryKey)
            return
        }

        var savedTabs: [SavedDraftTabSnapshot] = []
        savedTabs.reserveCapacity(min(dirtyTabs.count, maxPersistedDraftTabs))
        var remainingUTF16Length = maxPersistedDraftTotalUTF16Length
        for tab in dirtyTabs.prefix(maxPersistedDraftTabs) {
            guard remainingUTF16Length > 0 else { break }
            let content = tab.document.string()
            let nsContent = content as NSString
            let maximumLength = min(maxPersistedDraftUTF16Length, remainingUTF16Length)
            let clampedContent = nsContent.length > maximumLength
                ? nsContent.substring(to: maximumLength)
                : content
            remainingUTF16Length -= (clampedContent as NSString).length
            let fileBackedRecord = tab.fileBackedDocument?.restoreRecord
            let fileBackedSessionState = tab.fileBackedDocument?.sessionState
            savedTabs.append(
                SavedDraftTabSnapshot(
                    name: tab.name,
                    content: clampedContent,
                    language: tab.language,
                    fileURLString: tab.fileURL?.absoluteString,
                    lineEndingRawValue: tab.lineEnding.rawValue,
                    fileEncodingIdentifierRawValue: tab.fileEncoding.identifier.rawValue,
                    usesAutomaticFileEncoding: tab.usesAutomaticFileEncoding,
                    storageMode: fileBackedRecord == nil ? .materialized : .fileBacked,
                    fileBackedRestoreRecord: fileBackedRecord,
                    fileBackedSessionState: fileBackedSessionState
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

        guard let restoredSnapshot = restoredDraftSnapshotState(from: snapshots) else { return false }
        let mergedTabs = restoredSnapshot.tabs

        let restoredTabs = mergedTabs.map { saved in
            let restoredEncoding = saved.fileEncodingIdentifierRawValue
                .flatMap(TextEncodingDescriptor.Identifier.init(rawValue:))
                .map(TextEncodingDescriptor.init(identifier:))
                ?? .utf8
            return EditorViewModel.RestoredTabSnapshot(
                name: saved.name,
                content: saved.content,
                language: saved.language,
                fileURL: saved.fileURLString.flatMap(URL.init(string:)),
                languageLocked: true,
                isDirty: true,
                lastSavedFingerprint: nil,
                lastKnownFileModificationDate: nil,
                fileEncodingRawValue: restoredEncoding.encodingRawValue,
                fileEncoding: restoredEncoding,
                usesAutomaticFileEncoding: saved.usesAutomaticFileEncoding ?? true,
                lineEnding: saved.lineEndingRawValue.flatMap(TextLineEnding.init(rawValue:)) ?? .lf,
                fileBackedSessionState: saved.fileBackedSessionState
            )
        }
        viewModel.restoreTabsFromSnapshot(restoredTabs, selectedIndex: restoredSnapshot.selectedIndex)

        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: unsavedDraftSnapshotRegistryKey)
        return true
    }

    func clearUnsavedDraftSnapshots() {
        let defaults = UserDefaults.standard
        for key in defaults.stringArray(forKey: unsavedDraftSnapshotRegistryKey) ?? [] {
            defaults.removeObject(forKey: key)
        }
        defaults.removeObject(forKey: unsavedDraftSnapshotRegistryKey)
        lastPersistedDraftSignature = ""
    }

#if os(iOS) || os(visionOS)
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

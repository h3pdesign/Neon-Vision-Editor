import SwiftUI

extension ContentView {
    var currentDocumentTextForNavigation: String {
        liveEditorBufferText() ?? currentContentBinding.wrappedValue
    }

    var currentDocumentLineCount: Int {
        Self.lineCount(for: currentDocumentTextForNavigation)
    }

    var currentCaretLineNumber: Int? {
        let status = caretStatus
        guard let range = status.range(of: "Ln ") else { return nil }
        let suffix = status[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        return Int(digits)
    }

    var documentSymbols: [DocumentSymbolItem] {
        DocumentSymbolNavigator.symbols(content: currentDocumentTextForNavigation, language: currentLanguage)
    }

    var filteredDocumentSymbols: [DocumentSymbolItem] {
        let query = goToSymbolQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return documentSymbols }
        return documentSymbols.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || (item.line.map { String($0).contains(query) } ?? false)
        }
    }

    var quickSwitcherItems: [QuickFileSwitcherPanel.Item] {
        _ = recentFilesRefreshToken
        var items: [QuickFileSwitcherPanel.Item] = []
        let fileURLSet = Set(viewModel.tabs.compactMap { $0.fileURL?.standardizedFileURL.path })
        let commandItems: [QuickFileSwitcherPanel.Item] = [
            .init(id: "cmd:new_tab", title: "New Tab", subtitle: "Create a new empty tab", isPinned: false, canTogglePin: false),
            .init(id: "cmd:open_file", title: "Open File", subtitle: "Open files from disk", isPinned: false, canTogglePin: false),
            .init(id: "cmd:save_file", title: "Save", subtitle: "Save current tab", isPinned: false, canTogglePin: false),
            .init(id: "cmd:save_as", title: "Save As", subtitle: "Save current tab to a new file", isPinned: false, canTogglePin: false),
            .init(id: "cmd:find_replace", title: "Find and Replace", subtitle: "Search and replace in current document", isPinned: false, canTogglePin: false),
            .init(id: "cmd:find_in_files", title: "Find in Files", subtitle: "Search across project files", isPinned: false, canTogglePin: false),
            .init(id: "cmd:goto_line", title: "Go to Line", subtitle: "Jump to a line in the current document", isPinned: false, canTogglePin: false),
            .init(id: "cmd:goto_symbol", title: "Go to Symbol", subtitle: "Jump to a symbol in the current document", isPinned: false, canTogglePin: false),
            .init(id: "cmd:compare_disk", title: "Compare with Disk", subtitle: "Compare current tab against the saved file", isPinned: false, canTogglePin: false),
            .init(id: "cmd:compare_tabs", title: "Compare Open Tabs", subtitle: "Compare current tab with another open tab", isPinned: false, canTogglePin: false),
            .init(id: "cmd:toggle_sidebar", title: "Toggle Sidebar", subtitle: "Show or hide the outline sidebar", isPinned: false, canTogglePin: false),
            .init(id: "cmd:open_plist_structure", title: "Open plist Structure", subtitle: "Switch to structured plist mode when a plist is active", isPinned: false, canTogglePin: false)
        ]
        items.append(contentsOf: commandItems)

        for tab in viewModel.tabs {
            let subtitle = tab.fileURL?.path ?? "Open tab"
            items.append(
                QuickFileSwitcherPanel.Item(
                    id: "tab:\(tab.id.uuidString)",
                    title: tab.name,
                    subtitle: subtitle,
                    isPinned: false,
                    canTogglePin: false
                )
            )
        }

        for recent in RecentFilesStore.items(limit: 12) {
            let standardized = recent.url.standardizedFileURL.path
            if fileURLSet.contains(standardized) { continue }
            items.append(
                QuickFileSwitcherPanel.Item(
                    id: "file:\(standardized)",
                    title: recent.title,
                    subtitle: recent.subtitle,
                    isPinned: recent.isPinned,
                    canTogglePin: true
                )
            )
        }

        if projectFileIndexSnapshot.entries.isEmpty {
            for url in quickSwitcherProjectFileURLs {
                let standardized = url.standardizedFileURL.path
                if fileURLSet.contains(standardized) { continue }
                if items.contains(where: { $0.id == "file:\(standardized)" }) { continue }
                items.append(
                    QuickFileSwitcherPanel.Item(
                        id: "file:\(standardized)",
                        title: url.lastPathComponent,
                        subtitle: standardized,
                        isPinned: false,
                        canTogglePin: true
                    )
                )
            }
        } else {
            for entry in projectFileIndexSnapshot.entries {
                let standardized = entry.standardizedPath
                let subtitle = entry.relativePath == entry.displayName ? standardized : entry.relativePath
                if fileURLSet.contains(standardized) { continue }
                if items.contains(where: { $0.id == "file:\(standardized)" }) { continue }
                items.append(
                    QuickFileSwitcherPanel.Item(
                        id: "file:\(standardized)",
                        title: entry.displayName,
                        subtitle: subtitle,
                        isPinned: false,
                        canTogglePin: true
                    )
                )
            }
        }

        let query = quickSwitcherQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return Array(
                items
                    .sorted {
                        let leftPinned = $0.isPinned ? 1 : 0
                        let rightPinned = $1.isPinned ? 1 : 0
                        if leftPinned != rightPinned {
                            return leftPinned > rightPinned
                        }
                        return quickSwitcherRecencyScore(for: $0.id) > quickSwitcherRecencyScore(for: $1.id)
                    }
                    .prefix(300)
            )
        }

        let ranked = items.compactMap { item -> (QuickFileSwitcherPanel.Item, Int)? in
            guard let score = quickSwitcherMatchScore(for: item, query: query) else { return nil }
            let pinBoost = item.isPinned ? 400 : 0
            return (item, score + quickSwitcherRecencyScore(for: item.id) + pinBoost)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.title.localizedCaseInsensitiveCompare($1.0.title) == .orderedAscending
            }
            return $0.1 > $1.1
        }

        return Array(ranked.prefix(300).map(\.0))
    }

    var quickSwitcherStatusMessage: String {
        guard projectRootFolderURL != nil else { return "No project folder is open." }
        if isProjectFileIndexing {
            if projectFileIndexSnapshot.entries.isEmpty {
                return "Indexing project files for Quick Open…"
            }
            return "Refreshing indexed project files…"
        }
        if !projectFileIndexSnapshot.entries.isEmpty {
            let fileCount = projectFileIndexSnapshot.entries.count
            return "Using indexed project files (\(fileCount))."
        }
        if !quickSwitcherProjectFileURLs.isEmpty {
            return "Using the current project tree until indexing is available."
        }
        return "Project files will appear here after the folder is indexed."
    }

    var comparableOpenTabs: [TabData] {
        guard let selectedID = viewModel.selectedTab?.id else { return [] }
        return viewModel.tabs.filter { $0.id != selectedID }
    }

    var compareSheetBackgroundStyle: AnyShapeStyle {
#if os(macOS)
        if enableTranslucentWindow {
            switch macTranslucencyModeRaw {
            case "subtle":
                return AnyShapeStyle(Material.thickMaterial.opacity(0.72))
            case "vibrant":
                return AnyShapeStyle(Material.ultraThinMaterial.opacity(0.62))
            default:
                return AnyShapeStyle(Material.regularMaterial.opacity(0.68))
            }
        }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
#else
        if enableTranslucentWindow {
            return AnyShapeStyle(Material.ultraThinMaterial)
        }
        return AnyShapeStyle(Color(uiColor: .systemBackground))
#endif
    }

    func selectQuickSwitcherItem(_ item: QuickFileSwitcherPanel.Item) {
        rememberQuickSwitcherSelection(item.id)
        if item.id.hasPrefix("cmd:") {
            performQuickSwitcherCommand(item.id)
            return
        }
        if item.id.hasPrefix("tab:") {
            let raw = String(item.id.dropFirst(4))
            if let id = UUID(uuidString: raw) {
                viewModel.selectTab(id: id)
            }
            return
        }
        if item.id.hasPrefix("file:") {
            let path = String(item.id.dropFirst(5))
            openProjectFile(url: URL(fileURLWithPath: path))
        }
    }

    func toggleQuickSwitcherPin(_ item: QuickFileSwitcherPanel.Item) {
        guard item.canTogglePin, item.id.hasPrefix("file:") else { return }
        let path = String(item.id.dropFirst(5))
        RecentFilesStore.togglePinned(URL(fileURLWithPath: path))
        recentFilesRefreshToken = UUID()
    }

    var canCreateCodeSnapshot: Bool {
        !normalizedCodeSnapshotSelection().isEmpty
    }

    func presentCodeSnapshotComposer() {
        let selection = normalizedCodeSnapshotSelection()
        guard !selection.isEmpty else { return }
        let title = viewModel.selectedTab?.name ?? "Code Snapshot"
        codeSnapshotPayload = CodeSnapshotPayload(
            title: title,
            language: currentLanguage,
            text: selection
        )
    }

    func normalizedCodeSnapshotSelection() -> String {
        currentSelectionSnapshotText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func performQuickSwitcherCommand(_ commandID: String) {
        switch commandID {
        case "cmd:new_tab":
            viewModel.addNewTab()
        case "cmd:open_file":
            openFileFromToolbar()
        case "cmd:save_file":
            saveCurrentTabFromToolbar()
        case "cmd:save_as":
            saveCurrentTabAsFromToolbar()
        case "cmd:find_replace":
            showFindReplace = true
        case "cmd:find_in_files":
            showFindInFiles = true
        case "cmd:goto_line":
            goToLineInput = currentCaretLineNumber.map(String.init) ?? ""
            showGoToLine = true
        case "cmd:goto_symbol":
            goToSymbolQuery = ""
            showGoToSymbol = true
        case "cmd:compare_disk":
            compareCurrentTabAgainstDisk()
        case "cmd:compare_tabs":
            presentCompareTabsPicker()
        case "cmd:toggle_sidebar":
            viewModel.showSidebar.toggle()
        case "cmd:open_plist_structure":
            if isPlistDocument {
                plistViewMode = .structure
            } else {
                findStatusMessage = "Open a plist document to use structured plist mode."
            }
        default:
            break
        }
    }

    func compareCurrentTabAgainstDisk() {
        guard let tab = viewModel.selectedTab, tab.fileURL != nil else { return }
        Task {
            guard let snapshot = await viewModel.compareCurrentTabAgainstDiskSnapshot(tabID: tab.id) else { return }
            await presentDocumentDiff(snapshot)
        }
    }

    func presentCompareTabsPicker() {
        guard viewModel.selectedTab != nil else { return }
        showCompareTabsPicker = true
    }

    func compareSelectedTab(with tabID: UUID) {
        guard let selectedID = viewModel.selectedTab?.id,
              let snapshot = viewModel.compareTabsSnapshot(leftTabID: selectedID, rightTabID: tabID) else { return }
        showCompareTabsPicker = false
        Task {
            await Task.yield()
            await presentDocumentDiff(snapshot)
        }
    }

    func presentDocumentDiff(_ snapshot: EditorViewModel.DocumentComparisonSnapshot) async {
        let diff = await Task.detached(priority: .userInitiated) {
            DocumentDiffBuilder.build(leftContent: snapshot.leftContent, rightContent: snapshot.rightContent)
        }.value
        await MainActor.run {
            documentDiffPresentation = DocumentDiffPresentation(
                title: snapshot.title,
                leftTitle: snapshot.leftTitle,
                rightTitle: snapshot.rightTitle,
                diff: diff
            )
        }
    }

    func submitGoToLine(_ line: Int) {
        guard line > 0 else { return }
        var userInfo: [String: Any] = [:]
#if os(macOS)
        if let hostWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = hostWindowNumber
        }
#endif
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .moveCursorToLine, object: line, userInfo: userInfo)
        }
    }

    func selectDocumentSymbol(_ item: DocumentSymbolItem) {
        guard let line = item.line, line > 0 else { return }
        submitGoToLine(line)
    }

    func rememberQuickSwitcherSelection(_ itemID: String) {
        quickSwitcherRecentItemIDs.removeAll { $0 == itemID }
        quickSwitcherRecentItemIDs.insert(itemID, at: 0)
        if quickSwitcherRecentItemIDs.count > 30 {
            quickSwitcherRecentItemIDs = Array(quickSwitcherRecentItemIDs.prefix(30))
        }
        UserDefaults.standard.set(quickSwitcherRecentItemIDs, forKey: quickSwitcherRecentsDefaultsKey)
    }

    func quickSwitcherRecencyScore(for itemID: String) -> Int {
        guard let index = quickSwitcherRecentItemIDs.firstIndex(of: itemID) else { return 0 }
        return max(0, 120 - (index * 5))
    }

    func quickSwitcherPathComponents(for item: QuickFileSwitcherPanel.Item) -> [String] {
        item.subtitle
            .split(separator: "/")
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
    }

    func quickSwitcherTitleStem(for item: QuickFileSwitcherPanel.Item) -> String {
        URL(fileURLWithPath: item.title).deletingPathExtension().lastPathComponent.lowercased()
    }

    func quickSwitcherTokenPrefixScore(for query: String, in value: String, score: Int) -> Int? {
        let separators = CharacterSet.alphanumerics.inverted
        let tokens = value
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return tokens.contains(where: { $0.hasPrefix(query) }) ? score : nil
    }

    func quickSwitcherQueryTokens(for query: String) -> [String] {
        query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "_" || $0 == "-" || $0 == "." })
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func quickSwitcherMultiTokenScore(
        tokens: [String],
        title: String,
        subtitle: String,
        pathComponents: [String]
    ) -> Int? {
        guard tokens.count > 1 else { return nil }

        let titleTokens = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let subtitleTokens = subtitle
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let allTitlePrefix = tokens.allSatisfy { queryToken in
            titleTokens.contains(where: { $0.hasPrefix(queryToken) })
        }
        if allTitlePrefix {
            return 390
        }

        let allPathPrefix = tokens.allSatisfy { queryToken in
            pathComponents.contains(where: { $0.hasPrefix(queryToken) })
        }
        if allPathPrefix {
            return 340
        }

        let allDistributedPrefix = tokens.allSatisfy { queryToken in
            titleTokens.contains(where: { $0.hasPrefix(queryToken) }) ||
            subtitleTokens.contains(where: { $0.hasPrefix(queryToken) }) ||
            pathComponents.contains(where: { $0.hasPrefix(queryToken) })
        }
        if allDistributedPrefix {
            return 300
        }

        return nil
    }

    func quickSwitcherMatchScore(for item: QuickFileSwitcherPanel.Item, query: String) -> Int? {
        let normalizedQuery = query.lowercased()
        let queryTokens = quickSwitcherQueryTokens(for: query)
        let title = item.title.lowercased()
        let subtitle = item.subtitle.lowercased()
        let titleStem = quickSwitcherTitleStem(for: item)
        let pathComponents = quickSwitcherPathComponents(for: item)
        if title == normalizedQuery {
            return 420
        }
        if titleStem == normalizedQuery {
            return 400
        }
        if let score = quickSwitcherMultiTokenScore(
            tokens: queryTokens,
            title: title,
            subtitle: subtitle,
            pathComponents: pathComponents
        ) {
            return score
        }
        if let score = quickSwitcherTokenPrefixScore(for: normalizedQuery, in: title, score: 370) {
            return score
        }
        if title.hasPrefix(normalizedQuery) {
            return 350
        }
        if pathComponents.contains(normalizedQuery) {
            return 320
        }
        if pathComponents.contains(where: { $0.hasPrefix(normalizedQuery) }) {
            return 290
        }
        if title.contains(normalizedQuery) {
            return 240
        }
        if let score = quickSwitcherTokenPrefixScore(for: normalizedQuery, in: subtitle, score: 210) {
            return score
        }
        if subtitle.contains(normalizedQuery) {
            return 180
        }
        if isFuzzyMatch(needle: normalizedQuery, haystack: title) {
            return 120
        }
        if isFuzzyMatch(needle: normalizedQuery, haystack: subtitle) {
            return 90
        }
        return nil
    }

    func isFuzzyMatch(needle: String, haystack: String) -> Bool {
        if needle.isEmpty { return true }
        var cursor = haystack.startIndex
        for ch in needle {
            var found = false
            while cursor < haystack.endIndex {
                if haystack[cursor] == ch {
                    found = true
                    cursor = haystack.index(after: cursor)
                    break
                }
                cursor = haystack.index(after: cursor)
            }
            if !found { return false }
        }
        return true
    }

    func startFindInFiles() {
        guard let root = projectRootFolderURL else {
            findInFilesResults = []
            findInFilesSelectedMatchIDs = []
            findInFilesStatusMessage = "Open a project folder first."
            findInFilesSourceMessage = ""
            return
        }
        let query = findInFilesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            findInFilesResults = []
            findInFilesSelectedMatchIDs = []
            findInFilesStatusMessage = "Enter a search query."
            findInFilesSourceMessage = ""
            return
        }

        findInFilesTask?.cancel()
        let indexedProjectFileURLs = projectFileIndexSnapshot.fileURLs
        let candidateFiles = indexedProjectFileURLs.isEmpty ? nil : indexedProjectFileURLs
        let searchSourceMessage: String
        if candidateFiles == nil, isProjectFileIndexing {
            findInFilesStatusMessage = "Searching while project index updates…"
            searchSourceMessage = "Live filesystem scan while the project index refreshes."
        } else {
            findInFilesStatusMessage = "Searching…"
            if let candidateFiles {
                searchSourceMessage = "Searching \(candidateFiles.count) indexed project files."
            } else {
                searchSourceMessage = "Searching the live project tree because no index is available yet."
            }
        }
        findInFilesSourceMessage = searchSourceMessage

        let caseSensitive = findInFilesCaseSensitive
        findInFilesTask = Task {
            let results = await ContentView.findInFiles(
                root: root,
                candidateFiles: candidateFiles,
                query: query,
                caseSensitive: caseSensitive,
                maxResults: 500
            )
            guard !Task.isCancelled else { return }
            findInFilesResults = results
            findInFilesSelectedMatchIDs = Set(results.map(\.id))
            if results.isEmpty {
                findInFilesStatusMessage = "No matches found."
            } else {
                findInFilesStatusMessage = String.localizedStringWithFormat(
                    NSLocalizedString("%lld matches", comment: ""),
                    Int64(results.count)
                )
            }
            findInFilesSourceMessage = searchSourceMessage
        }
    }

    func clearFindInFiles() {
        findInFilesTask?.cancel()
        findInFilesReplaceTask?.cancel()
        isApplyingFindInFilesReplace = false
        findInFilesQuery = ""
        findInFilesReplaceQuery = ""
        findInFilesResults = []
        findInFilesSelectedMatchIDs = []
        findInFilesStatusMessage = ""
        findInFilesSourceMessage = ""
    }

    func toggleFindInFilesMatchSelection(_ matchID: String) {
        if findInFilesSelectedMatchIDs.contains(matchID) {
            findInFilesSelectedMatchIDs.remove(matchID)
        } else {
            findInFilesSelectedMatchIDs.insert(matchID)
        }
    }

    func selectAllFindInFilesMatches() {
        findInFilesSelectedMatchIDs = Set(findInFilesResults.map(\.id))
    }

    func clearFindInFilesSelection() {
        findInFilesSelectedMatchIDs = []
    }

    func cancelProjectWideReplaceFromFindInFiles() {
        findInFilesReplaceTask?.cancel()
        findInFilesStatusMessage = "Canceling replace…"
    }

    private struct FindInFilesReplaceOutcome {
        let changedFiles: [URL]
        let appliedMatches: Int
        let skippedMatches: Int
        let canceled: Bool
    }

    private nonisolated static func applySelectedFindInFilesReplacements(
        selectedMatches: [FindInFilesMatch],
        query: String,
        replacement: String,
        caseSensitive: Bool
    ) async -> FindInFilesReplaceOutcome {
        await Task.detached(priority: .userInitiated) {
            var matchesByFile: [String: [FindInFilesMatch]] = [:]
            for match in selectedMatches {
                matchesByFile[match.fileURL.standardizedFileURL.path, default: []].append(match)
            }

            var changedFiles: [URL] = []
            var appliedMatches = 0
            var skippedMatches = 0
            var canceled = false
            let compareOptions: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]

            for (_, fileMatches) in matchesByFile {
                if Task.isCancelled {
                    canceled = true
                    break
                }
                guard let firstMatch = fileMatches.first else { continue }
                let fileURL = firstMatch.fileURL
                let didStartScopedAccess = fileURL.startAccessingSecurityScopedResource()
                defer {
                    if didStartScopedAccess {
                        fileURL.stopAccessingSecurityScopedResource()
                    }
                }

                do {
                    var textEncoding: String.Encoding = .utf8
                    let originalText: String
                    if let decoded = try? String(contentsOf: fileURL, usedEncoding: &textEncoding) {
                        originalText = decoded
                    } else {
                        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
                        originalText = String(decoding: data, as: UTF8.self)
                        textEncoding = .utf8
                    }

                    var mutableText = originalText
                    var didChangeFile = false
                    let descendingMatches = fileMatches.sorted { lhs, rhs in
                        if lhs.rangeLocation != rhs.rangeLocation {
                            return lhs.rangeLocation > rhs.rangeLocation
                        }
                        return lhs.rangeLength > rhs.rangeLength
                    }

                    for match in descendingMatches {
                        if Task.isCancelled {
                            canceled = true
                            break
                        }
                        let nsMutable = mutableText as NSString
                        let range = NSRange(location: match.rangeLocation, length: match.rangeLength)
                        guard range.location >= 0, range.length >= 0, NSMaxRange(range) <= nsMutable.length else {
                            skippedMatches += 1
                            continue
                        }
                        let currentSegment = nsMutable.substring(with: range)
                        guard currentSegment.compare(query, options: compareOptions) == .orderedSame else {
                            skippedMatches += 1
                            continue
                        }
                        mutableText = nsMutable.replacingCharacters(in: range, with: replacement)
                        appliedMatches += 1
                        didChangeFile = true
                    }

                    if didChangeFile {
                        do {
                            try mutableText.write(to: fileURL, atomically: true, encoding: textEncoding)
                        } catch {
                            try mutableText.write(to: fileURL, atomically: true, encoding: .utf8)
                        }
                        changedFiles.append(fileURL)
                    }
                } catch {
                    skippedMatches += fileMatches.count
                }
            }

            return FindInFilesReplaceOutcome(
                changedFiles: changedFiles,
                appliedMatches: appliedMatches,
                skippedMatches: skippedMatches,
                canceled: canceled
            )
        }.value
    }

    func refreshOpenTabsAfterProjectReplace(changedFiles: [URL]) {
        guard !changedFiles.isEmpty else { return }
        let changedKeys = Set(changedFiles.map { $0.standardizedFileURL.path })
        let openTabs = viewModel.tabs
        for tab in openTabs {
            guard let fileURL = tab.fileURL else { continue }
            let key = fileURL.standardizedFileURL.path
            guard changedKeys.contains(key) else { continue }
            guard !tab.isReadOnlyPreview else { continue }
            guard !tab.isDirty else { continue }

            let didStartScopedAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartScopedAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { continue }
            let updatedText = String(decoding: data, as: UTF8.self)
            viewModel.updateTabContent(tabID: tab.id, content: updatedText)
            viewModel.markTabSaved(tabID: tab.id, fileURL: fileURL)
        }
    }

    func applyProjectWideReplaceFromFindInFiles() {
        guard !isApplyingFindInFilesReplace else { return }
        let query = findInFilesQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            findInFilesStatusMessage = "Enter a search query first."
            return
        }

        let selectedMatches = findInFilesResults.filter { findInFilesSelectedMatchIDs.contains($0.id) }
        guard !selectedMatches.isEmpty else {
            findInFilesStatusMessage = "Select at least one match to replace."
            return
        }

        let replacement = findInFilesReplaceQuery
        let caseSensitive = findInFilesCaseSensitive
        isApplyingFindInFilesReplace = true
        findInFilesStatusMessage = "Applying replace to selected matches…"

        findInFilesReplaceTask?.cancel()
        findInFilesReplaceTask = Task {
            let outcome = await Self.applySelectedFindInFilesReplacements(
                selectedMatches: selectedMatches,
                query: query,
                replacement: replacement,
                caseSensitive: caseSensitive
            )
            guard !Task.isCancelled else { return }

            isApplyingFindInFilesReplace = false
            refreshProjectBrowserState()
            refreshOpenTabsAfterProjectReplace(changedFiles: outcome.changedFiles)

            if outcome.canceled {
                findInFilesStatusMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Replace canceled after %lld changes.", comment: ""),
                    Int64(outcome.appliedMatches)
                )
            } else {
                findInFilesStatusMessage = String.localizedStringWithFormat(
                    NSLocalizedString("Replaced %lld matches in %lld files.", comment: ""),
                    Int64(outcome.appliedMatches),
                    Int64(outcome.changedFiles.count)
                )
            }
            if outcome.skippedMatches > 0 {
                findInFilesSourceMessage = String.localizedStringWithFormat(
                    NSLocalizedString("%lld skipped because file contents changed.", comment: ""),
                    Int64(outcome.skippedMatches)
                )
            } else {
                findInFilesSourceMessage = ""
            }

            startFindInFiles()
        }
    }

    func selectFindInFilesMatch(_ match: FindInFilesMatch) {
        openProjectFile(url: match.fileURL)
        var userInfo: [String: Any] = [
            EditorCommandUserInfo.rangeLocation: match.rangeLocation,
            EditorCommandUserInfo.rangeLength: match.rangeLength,
            EditorCommandUserInfo.focusEditor: true
        ]
#if os(macOS)
        if let hostWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = hostWindowNumber
        }
#endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            NotificationCenter.default.post(name: .moveCursorToRange, object: nil, userInfo: userInfo)
        }
    }

    func scheduleWordCountRefresh(for text: String) {
        let snapshot = text
        let shouldSkipWordCount = effectiveLargeFileModeEnabled || currentDocumentUTF16Length >= 300_000
        wordCountTask?.cancel()
        wordCountTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            let lineCount = Self.lineCount(for: snapshot)
            let wordCount = shouldSkipWordCount ? 0 : viewModel.wordCount(for: snapshot)
            await MainActor.run {
                statusLineCount = lineCount
                statusWordCount = wordCount
            }
        }
    }
}

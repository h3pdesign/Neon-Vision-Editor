import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension ContentView {
    private struct ProjectEditorOverrides: Decodable {
        let indentWidth: Int?
        let lineWrapEnabled: Bool?
    }

    func liveEditorBufferText() -> String? {
#if os(macOS)
        if let textView = activeEditorTextView() {
            return textView.string
        }
#elseif canImport(UIKit)
        if let textView = activeEditorInputTextView() {
            return textView.text
        }
#endif
        return nil
    }

    func showUpdaterDialog(checkNow: Bool = true) {
#if os(macOS)
        guard ReleaseRuntimePolicy.isUpdaterEnabledForCurrentDistribution else { return }
        showUpdateDialog = true
        if checkNow {
            Task {
                await appUpdateManager.checkForUpdates(source: .manual)
            }
        }
#endif
    }

    func openSettings(tab: String? = nil) {
        if let tab, !tab.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settingsActiveTab = ReleaseRuntimePolicy.settingsTab(from: tab)
        }
#if os(macOS)
        openSettingsAction()
#else
        showSettingsSheet = true
#endif
    }

    func openAPISettings() {
        openSettings(tab: "ai")
    }

    func openFileFromToolbar() {
#if os(macOS)
        viewModel.openFile()
#else
        showIOSFileImporter = true
#endif
    }

    func undoFromToolbar() {
#if os(macOS)
        if let textView = activeEditorTextView(),
           (textView.window?.firstResponder as? NSTextView) !== textView {
            textView.window?.makeFirstResponder(textView)
        }
        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
#elseif canImport(UIKit)
        if let textView = activeEditorInputTextView(),
           !textView.isFirstResponder {
            textView.becomeFirstResponder()
        }
        UIApplication.shared.sendAction(Selector(("undo:")), to: nil, from: nil, for: nil)
#endif
    }

    func saveCurrentTabFromToolbar() {
        guard let tab = viewModel.selectedTab else { return }
#if os(macOS)
        viewModel.saveFile(tabID: tab.id)
#else
        if tab.fileURL != nil {
            viewModel.saveFile(tabID: tab.id)
            if let updated = viewModel.tabs.first(where: { $0.id == tab.id }), !updated.isDirty {
                return
            }
        }
        iosExportTabID = tab.id
        iosExportDocument = PlainTextDocument(text: tab.content)
        iosExportFilename = suggestedExportFilename(for: tab)
        showIOSFileExporter = true
#endif
    }

    func saveCurrentTabAsFromToolbar() {
        guard let tab = viewModel.selectedTab else { return }
#if os(macOS)
        viewModel.saveFileAs(tabID: tab.id)
#else
        iosExportTabID = tab.id
        iosExportDocument = PlainTextDocument(text: tab.content)
        iosExportFilename = suggestedExportFilename(for: tab)
        showIOSFileExporter = true
#endif
    }

#if canImport(UIKit)
    func handleIOSImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            var openedCount = 0
            var unsupportedCount = 0
            var openedNames: [String] = []

            for url in urls {
                if viewModel.openFile(url: url) {
                    openedCount += 1
                    openedNames.append(url.lastPathComponent)
                } else {
                    unsupportedCount += 1
                    presentUnsupportedFileAlert(for: url)
                }
            }

            guard openedCount > 0 else {
                if unsupportedCount > 0 {
                    findStatusMessage = "Open failed: unsupported file type."
                } else {
                    findStatusMessage = "Open failed: selected files are no longer available."
                }
                recordDiagnostic("iOS import failed: no valid files in selection")
                return
            }

            if openedCount == 1, let name = openedNames.first {
                if unsupportedCount > 0 {
                    findStatusMessage = "Opened \(name) (\(unsupportedCount) unsupported ignored)"
                } else {
                    findStatusMessage = "Opened \(name)"
                }
            } else {
                if unsupportedCount > 0 {
                    findStatusMessage = "Opened \(openedCount) files (\(unsupportedCount) unsupported ignored)"
                } else {
                    findStatusMessage = "Opened \(openedCount) files"
                }
            }
            recordDiagnostic("iOS import success count: \(openedCount)")
        case .failure(let error):
            findStatusMessage = "Open failed: \(userFacingFileError(error))"
            recordDiagnostic("iOS import failed: \(error.localizedDescription)")
        }
    }

    func handleIOSExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if let tabID = iosExportTabID {
                viewModel.markTabSaved(tabID: tabID, fileURL: url)
            }
            findStatusMessage = "Saved to \(url.lastPathComponent)"
            recordDiagnostic("iOS export success: \(url.lastPathComponent)")
        case .failure(let error):
            findStatusMessage = "Save failed: \(userFacingFileError(error))"
            recordDiagnostic("iOS export failed: \(error.localizedDescription)")
        }
        iosExportTabID = nil
    }

    private func suggestedExportFilename(for tab: TabData) -> String {
        if tab.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Untitled.txt"
        }
        if tab.name.contains(".") {
            return tab.name
        }
        return "\(tab.name).txt"
    }

    private func userFacingFileError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSUserCancelledError:
                return "Cancelled."
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return "No permission for this location."
            case NSFileWriteOutOfSpaceError:
                return "Not enough storage space."
            default:
                break
            }
        }
        return nsError.localizedDescription
    }
#endif

    func clearEditorContent() {
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = ""
#if os(macOS)
        if let tv = activeEditorTextView() {
            tv.string = ""
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: 0, length: 0))
            tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
#endif
        caretStatus = "Ln 1, Col 1"
    }

    func requestClearEditorContent() {
        let hasText = !currentContentBinding.wrappedValue.isEmpty
        if confirmClearEditor && hasText {
            showClearEditorConfirmDialog = true
        } else {
            clearEditorContent()
        }
    }

    func toggleSidebarFromToolbar() {
#if os(iOS)
        if horizontalSizeClass == .compact {
            showCompactSidebarSheet.toggle()
            return
        }
#endif
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            viewModel.showSidebar.toggle()
        }
    }

    func toggleProjectSidebarFromToolbar() {
#if os(iOS)
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        if isPhone || horizontalSizeClass == .compact || horizontalSizeClass == nil {
            DispatchQueue.main.async {
                showCompactProjectSidebarSheet.toggle()
            }
            return
        }
#endif
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            showProjectStructureSidebar.toggle()
        }
    }

    func toggleMarkdownPreviewFromToolbar() {
        let nextValue = !showMarkdownPreviewPane
        showMarkdownPreviewPane = nextValue
#if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad && nextValue {
            showProjectStructureSidebar = false
            showCompactProjectSidebarSheet = false
        } else if UIDevice.current.userInterfaceIdiom == .phone && nextValue {
            dismissKeyboard()
        }
#endif
    }

    func closeAllTabsFromToolbar() {
        let dirtyTabIDs = viewModel.tabs.filter(\.isDirty).map(\.id)
        for tabID in dirtyTabIDs {
            guard viewModel.tabs.contains(where: { $0.id == tabID }) else { continue }
            viewModel.saveFile(tabID: tabID)
        }

        let tabIDsToClose = viewModel.tabs.map(\.id)
        for tabID in tabIDsToClose {
            guard viewModel.tabs.contains(where: { $0.id == tabID }) else { continue }
            viewModel.closeTab(tabID: tabID)
        }
    }

    func requestCloseAllTabsFromToolbar() {
        guard !viewModel.tabs.isEmpty else { return }
        showCloseAllTabsDialog = true
    }

    func dismissKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    func requestCloseTab(_ tab: TabData) {
        #if os(iOS)
        let shouldConfirmClose = tab.isDirty
        #else
        let shouldConfirmClose = tab.isDirty && confirmCloseDirtyTab
        #endif

        if shouldConfirmClose {
            pendingCloseTabID = tab.id
            showUnsavedCloseDialog = true
        } else {
            viewModel.closeTab(tabID: tab.id)
        }
    }

    func saveAndClosePendingTab() {
        guard let pendingCloseTabID,
              viewModel.tabs.contains(where: { $0.id == pendingCloseTabID }) else {
            self.pendingCloseTabID = nil
            return
        }

        viewModel.saveFile(tabID: pendingCloseTabID)

        if let updated = viewModel.tabs.first(where: { $0.id == pendingCloseTabID }),
           !updated.isDirty {
            viewModel.closeTab(tabID: pendingCloseTabID)
            self.pendingCloseTabID = nil
        } else {
            self.pendingCloseTabID = nil
        }
    }

    func discardAndClosePendingTab() {
        guard let pendingCloseTabID,
              let tab = viewModel.tabs.first(where: { $0.id == pendingCloseTabID }) else {
            self.pendingCloseTabID = nil
            return
        }
        viewModel.closeTab(tabID: tab.id)
        self.pendingCloseTabID = nil
    }

    func findNext() {
#if os(macOS)
        guard !findQuery.isEmpty, let tv = activeEditorTextView() else { return }
        if let win = tv.window {
            win.makeKeyAndOrderFront(nil)
            win.makeFirstResponder(tv)
            NSApp.activate(ignoringOtherApps: true)
        }
        findStatusMessage = ""
        let ns = tv.string as NSString
        let start = tv.selectedRange().upperBound
        let forwardRange = NSRange(location: start, length: max(0, ns.length - start))
        let wrapRange = NSRange(location: 0, length: max(0, start))

        if findUsesRegex {
            guard let regex = try? NSRegularExpression(pattern: findQuery, options: findCaseSensitive ? [] : [.caseInsensitive]) else {
                findStatusMessage = "Invalid regex pattern"
                NSSound.beep()
                return
            }
            let forwardMatch = regex.firstMatch(in: tv.string, options: [], range: forwardRange)
            let wrapMatch = regex.firstMatch(in: tv.string, options: [], range: wrapRange)
            if let match = forwardMatch ?? wrapMatch {
                tv.setSelectedRange(match.range)
                tv.scrollRangeToVisible(match.range)
            } else {
                findStatusMessage = "No matches found"
                NSSound.beep()
            }
        } else {
            let opts: NSString.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
            if let range = ns.range(of: findQuery, options: opts, range: forwardRange).toOptional() ?? ns.range(of: findQuery, options: opts, range: wrapRange).toOptional() {
                tv.setSelectedRange(range)
                tv.scrollRangeToVisible(range)
            } else {
                findStatusMessage = "No matches found"
                NSSound.beep()
            }
        }
#else
        guard !findQuery.isEmpty else { return }
        findStatusMessage = ""
        let source = currentContentBinding.wrappedValue
        let fingerprint = "\(findQuery)|\(findUsesRegex)|\(findCaseSensitive)"
        if fingerprint != iOSLastFindFingerprint {
            iOSLastFindFingerprint = fingerprint
            iOSFindCursorLocation = 0
        }

        guard let next = ReleaseRuntimePolicy.nextFindMatch(
            in: source,
            query: findQuery,
            useRegex: findUsesRegex,
            caseSensitive: findCaseSensitive,
            cursorLocation: iOSFindCursorLocation
        ) else {
            if findUsesRegex, (try? NSRegularExpression(pattern: findQuery, options: findCaseSensitive ? [] : [.caseInsensitive])) == nil {
                findStatusMessage = "Invalid regex pattern"
                return
            }
            findStatusMessage = "No matches found"
            return
        }

        iOSFindCursorLocation = next.nextCursorLocation
        NotificationCenter.default.post(
            name: .moveCursorToRange,
            object: nil,
            userInfo: [
                EditorCommandUserInfo.rangeLocation: next.range.location,
                EditorCommandUserInfo.rangeLength: next.range.length
            ]
        )
#endif
    }

    func replaceSelection() {
#if os(macOS)
        guard let tv = activeEditorTextView() else { return }
        let sel = tv.selectedRange()
        guard sel.length > 0 else { return }
        let selectedText = (tv.string as NSString).substring(with: sel)
        if findUsesRegex {
            guard let regex = try? NSRegularExpression(pattern: findQuery, options: findCaseSensitive ? [] : [.caseInsensitive]) else {
                findStatusMessage = "Invalid regex pattern"
                NSSound.beep()
                return
            }
            let fullSelected = NSRange(location: 0, length: (selectedText as NSString).length)
            let replacement = regex.stringByReplacingMatches(in: selectedText, options: [], range: fullSelected, withTemplate: replaceQuery)
            tv.insertText(replacement, replacementRange: sel)
        } else {
            tv.insertText(replaceQuery, replacementRange: sel)
        }
#else
        // iOS fallback: replace all exact text when regex is off.
        guard !findQuery.isEmpty else { return }
        if findUsesRegex {
            findStatusMessage = "Regex replace selection is currently available on macOS editor."
            return
        }
        currentContentBinding.wrappedValue = currentContentBinding.wrappedValue.replacingOccurrences(of: findQuery, with: replaceQuery)
#endif
    }

    func replaceAll() {
#if os(macOS)
        guard let tv = activeEditorTextView(), !findQuery.isEmpty else { return }
        findStatusMessage = ""
        let original = tv.string

        if findUsesRegex {
            guard let regex = try? NSRegularExpression(pattern: findQuery, options: findCaseSensitive ? [] : [.caseInsensitive]) else {
                findStatusMessage = "Invalid regex pattern"
                NSSound.beep()
                return
            }
            let fullRange = NSRange(location: 0, length: (original as NSString).length)
            let count = regex.numberOfMatches(in: original, options: [], range: fullRange)
            guard count > 0 else {
                findStatusMessage = "No matches found"
                NSSound.beep()
                return
            }
            let updated = regex.stringByReplacingMatches(in: original, options: [], range: fullRange, withTemplate: replaceQuery)
            tv.string = updated
            tv.didChangeText()
            findStatusMessage = "Replaced \(count) matches"
        } else {
            let opts: NSString.CompareOptions = findCaseSensitive ? [] : [.caseInsensitive]
            let nsOriginal = original as NSString
            var count = 0
            var searchLocation = 0
            while searchLocation < nsOriginal.length {
                let r = nsOriginal.range(of: findQuery, options: opts, range: NSRange(location: searchLocation, length: nsOriginal.length - searchLocation))
                if r.location == NSNotFound { break }
                count += 1
                searchLocation = max(r.location + max(r.length, 1), searchLocation + 1)
            }
            guard count > 0 else {
                findStatusMessage = "No matches found"
                NSSound.beep()
                return
            }
            let updated = nsOriginal.replacingOccurrences(of: findQuery, with: replaceQuery, options: opts, range: NSRange(location: 0, length: nsOriginal.length))
            tv.string = updated
            tv.didChangeText()
            findStatusMessage = "Replaced \(count) matches"
        }
#else
        guard !findQuery.isEmpty else { return }
        let original = currentContentBinding.wrappedValue
        if findUsesRegex {
            guard let regex = try? NSRegularExpression(pattern: findQuery, options: findCaseSensitive ? [] : [.caseInsensitive]) else {
                findStatusMessage = "Invalid regex pattern"
                return
            }
            let fullRange = NSRange(location: 0, length: (original as NSString).length)
            let count = regex.numberOfMatches(in: original, options: [], range: fullRange)
            guard count > 0 else {
                findStatusMessage = "No matches found"
                return
            }
            currentContentBinding.wrappedValue = regex.stringByReplacingMatches(in: original, options: [], range: fullRange, withTemplate: replaceQuery)
            findStatusMessage = "Replaced \(count) matches"
        } else {
            let updated = findCaseSensitive
                ? original.replacingOccurrences(of: findQuery, with: replaceQuery)
                : (original as NSString).replacingOccurrences(of: findQuery, with: replaceQuery, options: [.caseInsensitive], range: NSRange(location: 0, length: (original as NSString).length))
            if updated == original {
                findStatusMessage = "No matches found"
            } else {
                currentContentBinding.wrappedValue = updated
                findStatusMessage = "Replace complete"
            }
        }
#endif
    }

    func addNextMatchSelection() {
#if os(macOS)
        guard let textView = activeEditorTextView() else { return }
        let source = textView.string as NSString
        guard source.length > 0 else { return }

        let existing = textView.selectedRanges
        guard let primary = existing.last?.rangeValue, primary.length > 0 else {
            return
        }
        let needle = source.substring(with: primary)
        guard !needle.isEmpty else { return }

        let opts: NSString.CompareOptions = []
        let searchStart = NSMaxRange(primary)
        let forward = source.range(
            of: needle,
            options: opts,
            range: NSRange(location: min(searchStart, source.length), length: max(0, source.length - min(searchStart, source.length)))
        )
        let wrapped = source.range(
            of: needle,
            options: opts,
            range: NSRange(location: 0, length: min(primary.location, source.length))
        )
        guard let nextRange = forward.toOptional() ?? wrapped.toOptional() else { return }
        if existing.contains(where: { $0.rangeValue.location == nextRange.location && $0.rangeValue.length == nextRange.length }) {
            return
        }

        var updated = existing
        updated.append(NSValue(range: nextRange))
        textView.selectedRanges = updated
        textView.scrollRangeToVisible(nextRange)
#endif
    }

#if os(macOS)
    private func activeEditorTextView() -> NSTextView? {
        var candidates: [NSWindow] = []
        if let main = NSApp.mainWindow { candidates.append(main) }
        if let key = NSApp.keyWindow, key !== NSApp.mainWindow { candidates.append(key) }
        candidates.append(contentsOf: NSApp.windows.filter { $0.isVisible })

        for window in candidates {
            if window.isKind(of: NSPanel.self) { continue }
            if window.styleMask.contains(.docModalWindow) { continue }
            if let found = findEditorTextView(in: window.contentView) {
                return found
            }
            if let tv = window.firstResponder as? NSTextView, tv.isEditable {
                return tv
            }
        }
        return nil
    }

    private func findEditorTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView, let tv = scroll.documentView as? NSTextView, tv.isEditable {
            if tv.identifier?.rawValue == "NeonEditorTextView" {
                return tv
            }
        }
        if let tv = view as? NSTextView, tv.isEditable {
            if tv.identifier?.rawValue == "NeonEditorTextView" {
                return tv
            }
        }
        for subview in view.subviews {
            if let found = findEditorTextView(in: subview) {
                return found
            }
        }
        return nil
    }
#endif

#if canImport(UIKit)
    private func activeEditorInputTextView() -> UITextView? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        let windows = scenes
            .flatMap(\.windows)
            .sorted { lhs, rhs in
                if lhs.isKeyWindow != rhs.isKeyWindow {
                    return lhs.isKeyWindow && !rhs.isKeyWindow
                }
                return lhs.windowLevel < rhs.windowLevel
            }
        for window in windows {
            guard !window.isHidden, window.alpha > 0.01 else { continue }
            if let textView = findEditorInputTextView(in: window) {
                return textView
            }
        }
        return nil
    }

    private func findEditorInputTextView(in view: UIView?) -> UITextView? {
        guard let view else { return nil }
        if let textView = view as? EditorInputTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews {
            if let found = findEditorInputTextView(in: subview) {
                return found
            }
        }
        return nil
    }
#endif

    func applyWindowTranslucency(_ enabled: Bool) {
#if os(macOS)
        for window in NSApp.windows {
            window.isOpaque = !enabled
            window.backgroundColor = enabled ? .clear : NSColor.windowBackgroundColor
            // Keep window chrome layout stable across both modes to avoid frame/titlebar jumps.
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.styleMask.insert(.fullSizeContentView)
            if #available(macOS 13.0, *) {
                window.titlebarSeparatorStyle = .none
            }
        }
#endif
    }

    func openProjectFolder() {
#if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.showsHiddenFiles = false
        if panel.runModal() == .OK, let folderURL = panel.url {
            setProjectFolder(folderURL)
        }
#else
        showProjectFolderPicker = true
#endif
    }

    func refreshProjectTree() {
        guard let root = projectRootFolderURL else { return }
        projectTreeRefreshGeneration &+= 1
        let generation = projectTreeRefreshGeneration
        let supportedOnly = showSupportedProjectFilesOnly
        DispatchQueue.global(qos: .utility).async {
            let nodes = Self.buildProjectTree(at: root, supportedOnly: supportedOnly)
            DispatchQueue.main.async {
                guard generation == projectTreeRefreshGeneration else { return }
                guard projectRootFolderURL?.standardizedFileURL == root.standardizedFileURL else { return }
                projectTreeNodes = nodes
                quickSwitcherProjectFileURLs = Self.projectFileURLs(from: nodes)
            }
        }
    }

    func openProjectFile(url: URL) {
        guard EditorViewModel.isSupportedEditorFileURL(url) else {
            presentUnsupportedFileAlert(for: url)
            return
        }
        if viewModel.selectedTab?.fileURL?.standardizedFileURL == url.standardizedFileURL {
            return
        }
        if let existing = viewModel.tabs.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            viewModel.selectTab(id: existing.id)
            return
        }
        if !viewModel.openFile(url: url) {
            presentUnsupportedFileAlert(for: url)
        }
    }

    private nonisolated static func buildProjectTree(at root: URL, supportedOnly: Bool) -> [ProjectTreeNode] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        return readChildren(of: root, recursive: true, supportedOnly: supportedOnly)
    }

    func loadProjectTreeChildren(for directory: URL) -> [ProjectTreeNode] {
        Self.readChildren(of: directory, recursive: false, supportedOnly: showSupportedProjectFilesOnly)
    }

    func setProjectFolder(_ folderURL: URL) {
#if os(macOS) || canImport(UIKit)
        let standardizedTarget = folderURL.standardizedFileURL
        if let previous = projectFolderSecurityURL?.standardizedFileURL,
           previous != standardizedTarget {
            projectFolderSecurityURL?.stopAccessingSecurityScopedResource()
            projectFolderSecurityURL = nil
        }
        if projectFolderSecurityURL?.standardizedFileURL != standardizedTarget,
           folderURL.startAccessingSecurityScopedResource() {
            projectFolderSecurityURL = folderURL
        }
#endif
        projectRootFolderURL = folderURL
        projectTreeNodes = []
        quickSwitcherProjectFileURLs = []
        applyProjectEditorOverrides(from: folderURL)
        refreshProjectTree()
    }

    func clearProjectEditorOverrides() {
        projectOverrideIndentWidth = nil
        projectOverrideLineWrapEnabled = nil
        if viewModel.isLineWrapEnabled != settingsLineWrapEnabled {
            viewModel.isLineWrapEnabled = settingsLineWrapEnabled
        }
    }

    func applyProjectEditorOverrides(from folderURL: URL) {
        let configURL = folderURL.appendingPathComponent(".neon-editor.json")
        guard let data = try? Data(contentsOf: configURL, options: [.mappedIfSafe]),
              let overrides = try? JSONDecoder().decode(ProjectEditorOverrides.self, from: data) else {
            clearProjectEditorOverrides()
            return
        }

        if let width = overrides.indentWidth {
            projectOverrideIndentWidth = min(max(width, 2), 8)
        } else {
            projectOverrideIndentWidth = nil
        }

        projectOverrideLineWrapEnabled = overrides.lineWrapEnabled
        if let lineWrapEnabled = overrides.lineWrapEnabled,
           viewModel.isLineWrapEnabled != lineWrapEnabled {
            viewModel.isLineWrapEnabled = lineWrapEnabled
        } else if overrides.lineWrapEnabled == nil, viewModel.isLineWrapEnabled != settingsLineWrapEnabled {
            viewModel.isLineWrapEnabled = settingsLineWrapEnabled
        }
    }

    private nonisolated static func readChildren(of directory: URL, recursive: Bool, supportedOnly: Bool) -> [ProjectTreeNode] {
        if Task.isCancelled { return [] }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey, .nameKey]
        guard let urls = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants, .skipsSubdirectoryDescendants]) else {
            return []
        }

        let sorted = urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        var nodes: [ProjectTreeNode] = []
        for url in sorted {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isHidden == true { continue }
            let isDirectory = values.isDirectory == true
            if !isDirectory && supportedOnly && !EditorViewModel.isSupportedEditorFileURL(url) {
                continue
            }
            let children = (isDirectory && recursive) ? readChildren(of: url, recursive: true, supportedOnly: supportedOnly) : []
            nodes.append(
                ProjectTreeNode(
                    url: url,
                    isDirectory: isDirectory,
                    children: children
                )
            )
        }
        return nodes
    }

    private func presentUnsupportedFileAlert(for url: URL) {
        unsupportedFileName = url.lastPathComponent
        findStatusMessage = "Unsupported file type."
        showUnsupportedFileAlert = true
    }

    static func projectFileURLs(from nodes: [ProjectTreeNode]) -> [URL] {
        var results: [URL] = []
        var stack = nodes
        while let node = stack.popLast() {
            if node.isDirectory {
                stack.append(contentsOf: node.children)
            } else {
                results.append(node.url)
            }
        }
        return results
    }

    nonisolated static func findInFiles(
        root: URL,
        query: String,
        caseSensitive: Bool,
        maxResults: Int
    ) async -> [FindInFilesMatch] {
        await Task.detached(priority: .userInitiated) {
            #if os(macOS)
            if let ripgrepMatches = findInFilesWithRipgrep(
                root: root,
                query: query,
                caseSensitive: caseSensitive,
                maxResults: maxResults
            ) {
                return ripgrepMatches
            }
            #endif

            let files = searchableProjectFiles(at: root)
            var results: [FindInFilesMatch] = []
            results.reserveCapacity(min(maxResults, 200))

            for file in files {
                if Task.isCancelled || results.count >= maxResults { break }
                let matches = findMatches(
                    in: file,
                    query: query,
                    caseSensitive: caseSensitive,
                    maxRemaining: maxResults - results.count
                )
                if !matches.isEmpty {
                    results.append(contentsOf: matches)
                }
            }
            return results
        }.value
    }

#if os(macOS)
    private nonisolated static func findInFilesWithRipgrep(
        root: URL,
        query: String,
        caseSensitive: Bool,
        maxResults: Int
    ) -> [FindInFilesMatch]? {
        guard maxResults > 0 else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = root
        process.arguments = [
            "rg",
            "--json",
            "--line-number",
            "--column",
            "--max-count",
            String(maxResults),
            caseSensitive ? "-s" : "-i",
            query,
            root.path
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            return nil
        }
        guard !data.isEmpty else { return [] }

        var results: [FindInFilesMatch] = []
        results.reserveCapacity(min(maxResults, 200))
        var contentByPath: [String: String] = [:]
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            if results.count >= maxResults { break }
            guard let eventData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
                  (json["type"] as? String) == "match",
                  let payload = json["data"] as? [String: Any],
                  let path = (payload["path"] as? [String: Any])?["text"] as? String,
                  let lineNumber = payload["line_number"] as? Int,
                  let linesDict = payload["lines"] as? [String: Any],
                  let lineText = linesDict["text"] as? String,
                  let submatches = payload["submatches"] as? [[String: Any]],
                  let first = submatches.first,
                  let start = first["start"] as? Int,
                  let end = first["end"] as? Int else {
                continue
            }

            let column = max(1, start + 1)
            let length = max(1, end - start)
            let snippet = lineText.trimmingCharacters(in: .newlines)
            let fileURL = URL(fileURLWithPath: path)
            let fileContent: String = {
                if let cached = contentByPath[path] {
                    return cached
                }
                let loaded = String(decoding: (try? Data(contentsOf: fileURL, options: [.mappedIfSafe])) ?? Data(), as: UTF8.self)
                contentByPath[path] = loaded
                return loaded
            }()
            let offset = utf16LocationForLine(content: fileContent, lineOneBased: lineNumber)
            results.append(
                FindInFilesMatch(
                    id: "\(path)#\(offset + start)",
                    fileURL: fileURL,
                    line: lineNumber,
                    column: column,
                    snippet: snippet.isEmpty ? "(empty line)" : snippet,
                    rangeLocation: offset + start,
                    rangeLength: length
                )
            )
        }
        return results
    }

    private nonisolated static func utf16LocationForLine(content: String, lineOneBased: Int) -> Int {
        guard lineOneBased > 1 else { return 0 }
        var line = 1
        var utf16Offset = 0
        for codeUnit in content.utf16 {
            if line >= lineOneBased { break }
            utf16Offset += 1
            if codeUnit == 10 {
                line += 1
            }
        }
        return utf16Offset
    }
#endif

    private nonisolated static func searchableProjectFiles(at root: URL) -> [URL] {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard values.isHidden != true, values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            if size <= 0 || size > 2_000_000 { continue }
            files.append(url)
        }
        return files
    }

    private nonisolated static func findMatches(
        in fileURL: URL,
        query: String,
        caseSensitive: Bool,
        maxRemaining: Int
    ) -> [FindInFilesMatch] {
        guard maxRemaining > 0 else { return [] }
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else { return [] }
        if data.prefix(4096).contains(0) { return [] }
        let content = String(decoding: data, as: UTF8.self)
        let nsContent = content as NSString
        if nsContent.length == 0 { return [] }

        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let queryLength = (query as NSString).length
        if queryLength == 0 { return [] }

        var output: [FindInFilesMatch] = []
        output.reserveCapacity(min(maxRemaining, 16))

        var searchRange = NSRange(location: 0, length: nsContent.length)
        while searchRange.length > 0 && output.count < maxRemaining {
            let found = nsContent.range(of: query, options: options, range: searchRange)
            if found.location == NSNotFound { break }

            let lineRange = nsContent.lineRange(for: NSRange(location: found.location, length: 0))
            let lineTextRaw = nsContent.substring(with: lineRange).trimmingCharacters(in: .newlines)
            let prefixRange = NSRange(location: 0, length: found.location)
            let line = nsContent.substring(with: prefixRange).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            let column = found.location - lineRange.location + 1
            let safeSnippet = lineTextRaw.isEmpty ? "(empty line)" : lineTextRaw

            output.append(
                FindInFilesMatch(
                    id: "\(fileURL.path)#\(found.location)",
                    fileURL: fileURL,
                    line: line,
                    column: max(1, column),
                    snippet: safeSnippet,
                    rangeLocation: found.location,
                    rangeLength: found.length
                )
            )

            let nextLocation = found.location + max(1, found.length)
            if nextLocation >= nsContent.length { break }
            searchRange = NSRange(location: nextLocation, length: nsContent.length - nextLocation)
        }

        return output
    }
}

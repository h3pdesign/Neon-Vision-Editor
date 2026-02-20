import SwiftUI
import Foundation
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension ContentView {
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
        settingsActiveTab = ReleaseRuntimePolicy.settingsTab(from: tab)
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

    func saveCurrentTabFromToolbar() {
        guard let tab = viewModel.selectedTab else { return }
#if os(macOS)
        viewModel.saveFile(tab: tab)
#else
        if tab.fileURL != nil {
            viewModel.saveFile(tab: tab)
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

#if canImport(UIKit)
    func handleIOSImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            var openedCount = 0
            var openedNames: [String] = []

            for url in urls {
                let didStart = url.startAccessingSecurityScopedResource()
                defer {
                    if didStart {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                guard FileManager.default.fileExists(atPath: url.path) else {
                    recordDiagnostic("iOS import skipped (missing file): \(url.path)")
                    continue
                }

                viewModel.openFile(url: url)
                openedCount += 1
                openedNames.append(url.lastPathComponent)
            }

            guard openedCount > 0 else {
                findStatusMessage = "Open failed: selected files are no longer available."
                recordDiagnostic("iOS import failed: no valid files in selection")
                return
            }

            if openedCount == 1, let name = openedNames.first {
                findStatusMessage = "Opened \(name)"
            } else {
                findStatusMessage = "Opened \(openedCount) files"
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
        currentContentBinding.wrappedValue = ""
#if os(macOS)
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView {
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

    func dismissKeyboard() {
#if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
#endif
    }

    func requestCloseTab(_ tab: TabData) {
        if tab.isDirty && confirmCloseDirtyTab {
            pendingCloseTabID = tab.id
            showUnsavedCloseDialog = true
        } else {
            viewModel.closeTab(tab: tab)
        }
    }

    func saveAndClosePendingTab() {
        guard let pendingCloseTabID,
              let tab = viewModel.tabs.first(where: { $0.id == pendingCloseTabID }) else {
            self.pendingCloseTabID = nil
            return
        }

        viewModel.saveFile(tab: tab)

        if let updated = viewModel.tabs.first(where: { $0.id == pendingCloseTabID }),
           !updated.isDirty {
            viewModel.closeTab(tab: updated)
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
        viewModel.closeTab(tab: tab)
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
        DispatchQueue.global(qos: .utility).async {
            let nodes = buildProjectTree(at: root)
            DispatchQueue.main.async {
                guard generation == projectTreeRefreshGeneration else { return }
                guard projectRootFolderURL?.standardizedFileURL == root.standardizedFileURL else { return }
                projectTreeNodes = nodes
                quickSwitcherProjectFileURLs = projectFileURLs(from: nodes)
            }
        }
    }

    func openProjectFile(url: URL) {
        if let existing = viewModel.tabs.first(where: { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }) {
            viewModel.selectedTabID = existing.id
            return
        }
        viewModel.openFile(url: url)
    }

    private func buildProjectTree(at root: URL) -> [ProjectTreeNode] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else { return [] }
        return readChildren(of: root, recursive: false)
    }

    func loadProjectTreeChildren(for directory: URL) -> [ProjectTreeNode] {
        readChildren(of: directory, recursive: false)
    }

    func setProjectFolder(_ folderURL: URL) {
#if canImport(UIKit)
        if let previous = projectFolderSecurityURL {
            previous.stopAccessingSecurityScopedResource()
        }
        if folderURL.startAccessingSecurityScopedResource() {
            projectFolderSecurityURL = folderURL
        }
#endif
        projectRootFolderURL = folderURL
        projectTreeNodes = []
        quickSwitcherProjectFileURLs = []
        refreshProjectTree()
    }

    private func readChildren(of directory: URL, recursive: Bool) -> [ProjectTreeNode] {
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
            let children = (isDirectory && recursive) ? readChildren(of: url, recursive: true) : []
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

    func projectFileURLs(from nodes: [ProjectTreeNode]) -> [URL] {
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
}

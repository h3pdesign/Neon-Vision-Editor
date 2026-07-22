import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

private struct FileTabBarContentMinXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FileTabBarScrollFadeMask<Mask: View>: ViewModifier {
    let mask: Mask

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(macOS)
        if #available(macOS 26.0, *) {
            content.mask(mask)
        } else {
            // SwiftUI masks can swallow tab-button mouse events on pre-26 macOS.
            content
        }
#else
        content.mask(mask)
#endif
    }
}

#if os(macOS)
private struct FileTabDropDelegate: DropDelegate {
    let destinationTabID: UUID
    let tabWidth: CGFloat
    @Binding var insertionTabID: UUID?
    @Binding var insertionBefore: Bool
    let moveTab: (UUID, UUID, Bool) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !info.itemProviders(for: [.plainText]).isEmpty
    }

    func dropEntered(info: DropInfo) {
        updateInsertionMarker(for: info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateInsertionMarker(for: info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if insertionTabID == destinationTabID {
            insertionTabID = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertBefore = info.location.x < tabWidth / 2
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? String,
                  let draggedTabID = UUID(uuidString: identifier),
                  draggedTabID != destinationTabID else {
                return
            }
            DispatchQueue.main.async {
                moveTab(draggedTabID, destinationTabID, insertBefore)
                if insertionTabID == destinationTabID {
                    insertionTabID = nil
                }
            }
        }
        return true
    }

    private func updateInsertionMarker(for location: CGPoint) {
        let shouldInsertBefore = location.x < tabWidth / 2
        guard insertionTabID != destinationTabID || insertionBefore != shouldInsertBefore else { return }
        insertionTabID = destinationTabID
        insertionBefore = shouldInsertBefore
    }
}
#endif

extension ContentView {
#if os(iOS) || os(visionOS)
    @ViewBuilder
    var iOSUnifiedTopChromeHost: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if isIPadToolbarLayout {
                    iPadUnifiedToolbarRow
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                } else {
                    iPhoneUnifiedToolbarRow
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                tabBarView
            }
            .background(
                enableTranslucentWindow
                ? AnyShapeStyle(.ultraThinMaterial)
                : AnyShapeStyle(iOSNonTranslucentSurfaceColor)
            )
        }
        .overlay(alignment: .bottom) {
            if !brainDumpLayoutEnabled && shouldPinFloatingStatusToTop {
                iOSPinnedEditingStatusRow
                    // Overlay the editor instead of reserving a separate opaque strip.
                    .offset(y: 48)
            }
        }
    }

    private var iOSPinnedEditingStatusRow: some View {
        HStack(spacing: 8) {
            if shouldEmbedMarkdownFormattingInMobileStatusRow {
                iPhoneMarkdownFormattingStatusControl
            }
            Spacer(minLength: 0)
            floatingStatusPill
        }
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var isPhoneCompactStatusMode: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && (isPhoneEditorFocused || isPhoneSoftwareKeyboardVisible)
    }

    private var shouldUseEditingMobileStatusPreset: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
        && mobileEditingStatusPresetEnabled
        && isPhoneCompactStatusMode
    }

    var shouldPinFloatingStatusToTop: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && isPhoneSoftwareKeyboardVisible
    }

    private var floatingStatusPillText: String {
        if let externalStatus = viewModel.externalFileRefreshStatus {
            return externalStatus.message
        }
        if !projectRefreshStatusMessage.isEmpty {
            return projectRefreshStatusMessage
        }
        if shouldUseEditingMobileStatusPreset {
            let items = editingMobileStatusItems
            let maxItemCount = isPhoneStatusBarExpanded ? items.count : 1
            return statusBarText(for: items, maxItemCount: maxItemCount)
        }
        let maxItemCount: Int? = {
            if isPhoneCompactStatusMode {
                return isPhoneStatusBarExpanded ? mobileStatusBarMaxItemCount : 1
            }
            return mobileStatusBarMaxItemCount
        }()
        let base = statusBarText(maxItemCount: maxItemCount)
        let suffixes = [largeFileStatusBadgeText, remoteSessionStatusBadgeText].filter { !$0.isEmpty }
        if suffixes.isEmpty {
            return base
        }
        return "\(base) • \(suffixes.joined(separator: " • "))"
    }

    var floatingStatusPill: some View {
        GlassSurface(
            enabled: shouldUseLiquidGlass,
            material: primaryGlassMaterial,
            fallbackColor: toolbarFallbackColor,
            shape: .capsule,
            chromeStyle: .single
        ) {
            Text(floatingStatusPillText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(iOSToolbarForegroundColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isPhoneCompactStatusMode else { return }
            isPhoneStatusBarExpanded.toggle()
            if isPhoneStatusBarExpanded {
                schedulePhoneStatusAutoCollapse()
            } else {
                cancelPhoneStatusAutoCollapse()
            }
        }
        .accessibilityLabel("Editor status")
        .accessibilityValue(floatingStatusPillText)
        .accessibilityHint(isPhoneCompactStatusMode ? "Double tap to expand or collapse editor status details" : "")
    }

    var iOSToolbarForegroundColor: Color {
        if toolbarIconsBlueIOS {
            return NeonUIStyle.accentBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
    }
#endif

    private var macStatusBarText: String {
        statusBarText(maxItemCount: nil)
    }

    private func statusBarText(maxItemCount: Int?) -> String {
        statusBarText(for: statusBarItems(), maxItemCount: maxItemCount)
    }

    private func statusBarText(for allItems: [String], maxItemCount: Int?) -> String {
        var items = allItems
        var hiddenItemCount = 0
        if let maxItemCount {
            hiddenItemCount = max(0, allItems.count - maxItemCount)
            items = Array(allItems.prefix(maxItemCount))
        }
        if items.isEmpty {
            items = ["Ready"]
        }
        if hiddenItemCount > 0 {
            items.append("+\(hiddenItemCount)")
        }
        return "\(items.joined(separator: " • "))\(vimStatusSuffix)"
    }

    private var editingMobileStatusItems: [String] {
        var items: [String] = [caretStatus]
        if let selection = selectionStatusText {
            items.append(selection)
        }
        if !largeFileStatusBadgeText.isEmpty {
            items.append(largeFileStatusBadgeText)
        }
        return items
    }

#if os(iOS) || os(visionOS)
    @MainActor
    func handlePhoneKeyboardVisibilityChange(isVisible: Bool) {
        isPhoneSoftwareKeyboardVisible = isVisible
        cancelPhoneStatusAutoCollapse()
        isPhoneStatusBarExpanded = false
    }

    @MainActor
    func schedulePhoneStatusAutoCollapse() {
        cancelPhoneStatusAutoCollapse()
        guard UIDevice.current.userInterfaceIdiom == .phone, isPhoneCompactStatusMode else { return }
        phoneStatusAutoCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            isPhoneStatusBarExpanded = false
            phoneStatusAutoCollapseTask = nil
        }
    }

    @MainActor
    func cancelPhoneStatusAutoCollapse() {
        phoneStatusAutoCollapseTask?.cancel()
        phoneStatusAutoCollapseTask = nil
    }
#endif

    private func statusBarItems() -> [String] {
        var items: [String] = []
        if statusBarShowCursor {
            items.append(caretStatus)
        }
        if statusBarShowLineCount {
            items.append("Lines: \(statusLineCount)")
        }
        if statusBarShowWordCount && !effectiveLargeFileModeEnabled {
            items.append("Words: \(statusWordCount)")
        }
        if statusBarShowEncoding {
            items.append(viewModel.selectedTab?.fileEncoding.displayName ?? "UTF-8")
        }
        if statusBarShowLineEndings {
            items.append(lineEndingStatusText)
        }
        if statusBarShowIndentation {
            items.append(indentationStatusText)
        }
        if statusBarShowSelection, let selection = selectionStatusText {
            items.append(selection)
        }
        if statusBarShowFileSize {
            items.append(fileSizeStatusText)
        }
        if statusBarShowGit, let git = gitStatusText {
            items.append(git)
        }
        return items
    }

#if os(iOS) || os(visionOS)
    private var mobileStatusBarMaxItemCount: Int {
        UIDevice.current.userInterfaceIdiom == .pad ? 5 : 3
    }
#endif

    private var lineEndingStatusText: String {
        if currentContent.contains("\r\n") { return "CRLF" }
        if currentContent.contains("\r") { return "CR" }
        return "LF"
    }

    private var indentationStatusText: String {
        let label = indentStyle == "tabs" ? "Tabs" : "Spaces"
        return "\(label): \(indentWidth)"
    }

    private var selectionStatusText: String? {
        guard !currentSelectionSnapshotText.isEmpty else { return nil }
        let lines = selectionLineCount(for: currentSelectionSnapshotText)
        if lines > 1 {
            return "Sel: \(lines) lines"
        }
        return "Sel: \(currentSelectionSnapshotText.count) chars"
    }

    private func selectionLineCount(for text: String) -> Int {
        guard !text.isEmpty else { return 1 }
        var count = 1
        for codeUnit in text.utf16 where codeUnit == 10 {
            count += 1
        }
        return count
    }

    private var fileSizeStatusText: String {
        ByteCountFormatter.string(fromByteCount: Int64(currentContent.utf8.count), countStyle: .file)
    }

    private var gitStatusText: String? {
        guard gitViewModel.isRepo else { return nil }
        let branch = gitViewModel.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let branchText = branch.isEmpty ? "Git" : branch
        let changedCount = gitViewModel.entries.count
        if changedCount > 0 {
            return "\(branchText): \(changedCount) changes"
        }
        return branchText
    }

    private var externalFileRefreshStatusSystemImage: String {
        switch viewModel.externalFileRefreshStatus?.kind {
        case .refreshing: return "arrow.clockwise"
        case .refreshed: return "checkmark.circle"
        case .needsReview: return "exclamationmark.triangle"
        case nil: return "arrow.clockwise"
        }
    }

    @ViewBuilder
    var wordCountView: some View {
        HStack(spacing: 10) {
            if let externalStatus = viewModel.externalFileRefreshStatus {
                Label(
                    externalStatus.message,
                    systemImage: externalFileRefreshStatusSystemImage
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(externalStatus.kind == .needsReview ? Color.orange : Color.secondary)
                .lineLimit(1)
                .accessibilityLabel("External file refresh status")
                .accessibilityValue(externalStatus.message)
                .padding(.leading, 12)
            }

            if !projectRefreshStatusMessage.isEmpty {
                Label(
                    projectRefreshStatusMessage,
                    systemImage: isProjectFileIndexing ? "arrow.clockwise" : "checkmark.circle"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel("Project refresh status")
                .accessibilityValue(projectRefreshStatusMessage)
                .padding(.leading, 12)
            }

            if droppedFileLoadInProgress {
                HStack(spacing: 8) {
                    if droppedFileProgressDeterminate {
                        ProgressView(value: droppedFileLoadProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 130)
                    } else {
                        ProgressView()
                            .frame(width: 18)
                    }
                    Text(droppedFileProgressDeterminate ? "\(droppedFileLoadLabel) \(importProgressPercentText)" : "\(droppedFileLoadLabel) Loading…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 12)
            }

            if effectiveLargeFileModeEnabled {
                largeFileStatusBadge
                Picker("Large file open mode", selection: $largeFileOpenModeRaw) {
                    Text("Standard").tag("standard")
                    Text("Responsive").tag("deferred")
                    Text("Plain Text").tag("plainText")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                .fixedSize(horizontal: false, vertical: true)
                .controlSize(.small)
                .accessibilityLabel("Large file open mode")
                .accessibilityHint(largeFileModeFeatureDetails)
            }
            if !remoteSessionStatusBadgeText.isEmpty {
                remoteSessionBadge
            }
            if !selectedRemoteDocumentBadgeText.isEmpty {
                selectedRemoteDocumentBadge
            }
            Spacer()
            Text(macStatusBarText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, 8)
                .padding(.trailing, 16)
        }
        .background(editorSurfaceBackgroundStyle)
    }

    private var largeFileStatusBadge: some View {
        Text(largeFileStatusBadgeText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
            )
            .accessibilityLabel("Large file mode")
            .accessibilityValue(currentLargeFileOpenModeLabel)
            .accessibilityHint(largeFileModeFeatureDetails)
    }

    private var remoteSessionBadge: some View {
        Text(remoteSessionStatusBadgeText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(remoteSessionBadgeForegroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(remoteSessionBadgeBackgroundColor)
            )
            .accessibilityLabel("Remote session status")
            .accessibilityValue(remoteSessionBadgeAccessibilityValue)
    }

    private var selectedRemoteDocumentBadgeText: String {
        guard let tab = viewModel.selectedTab, tab.isRemoteDocument else { return "" }
        return tab.isReadOnlyPreview ? "Remote Document • Read-Only" : "Remote Document • Editable"
    }

    private var selectedRemoteDocumentBadge: some View {
        Text(selectedRemoteDocumentBadgeText)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
            )
            .accessibilityLabel("Selected document status")
            .accessibilityValue(selectedRemoteDocumentBadgeText)
    }

    var largeFileSessionBadge: some View {
        Menu {
            largeFileOpenModeMenuContent
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NeonUIStyle.accentBlue)
                Text(largeFileStatusBadgeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Large file session")
        .accessibilityValue(currentLargeFileOpenModeLabel)
        .accessibilityHint("\(largeFileModeFeatureDetails) Open large file mode options.")
    }

    @ViewBuilder
    private var largeFileOpenModeMenuContent: some View {
        Section("Large File Mode") {
            Text("\(currentDocumentFileSizeText) • \(viewModel.selectedTab?.isPartialFilePreview == true ? "Read-Only" : "Editable")")
            Text(largeFileModeFeatureDetails)
        }
        Divider()
        Button {
            largeFileOpenModeRaw = "standard"
        } label: {
            largeFileOpenModeMenuLabel(title: "Standard", isSelected: largeFileOpenModeRaw == "standard")
        }
        Button {
            largeFileOpenModeRaw = "deferred"
        } label: {
            largeFileOpenModeMenuLabel(title: "Responsive", isSelected: largeFileOpenModeRaw == "deferred")
        }
        Button {
            largeFileOpenModeRaw = "plainText"
        } label: {
            largeFileOpenModeMenuLabel(title: "Plain Text", isSelected: largeFileOpenModeRaw == "plainText")
        }
    }

    private func largeFileOpenModeMenuLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            if isSelected {
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private func tabRemoteBadge(for tab: TabData) -> some View {
        if tab.isRemoteDocument {
            Text("Remote")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(viewModel.selectedTabID == tab.id ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(viewModel.selectedTabID == tab.id ? 0.16 : 0.10))
                )
        }
    }

    private func tabAccessibilityLabel(for tab: TabData) -> String {
        var parts: [String] = [tab.name]
        if tab.isRemoteDocument {
            parts.append(tab.isReadOnlyPreview ? "remote read only document" : "remote editable document")
        } else {
            parts.append("local document")
        }
        if tab.isDirty {
            parts.append("unsaved changes")
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    var tabBarView: some View {
        VStack(spacing: 0) {
#if os(macOS)
            if #available(macOS 26.0, *) {
                scrollableFileTabBar
            } else {
                macLegacyFileTabBar
            }
#else
            scrollableFileTabBar
#endif
#if os(iOS) || os(visionOS)
            EmptyView()
#else
            tabBarBottomDivider
#endif
        }
        .frame(minHeight: 42, maxHeight: 42, alignment: .center)
#if os(macOS)
        .background(editorSurfaceBackgroundStyle.opacity(usesAnySidebarTabTransition ? 0 : 1))
#else
        .background(
            enableTranslucentWindow
            ? AnyShapeStyle(.ultraThinMaterial)
            : (useIOSUnifiedSolidSurfaces ? AnyShapeStyle(iOSNonTranslucentSurfaceColor) : AnyShapeStyle(Color(.systemBackground)))
        )
        .contentShape(Rectangle())
        .zIndex(10)
#endif
    }

    private var scrollableFileTabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                fileTabBarContent
                    .padding(5)
                    .background(
                        fileTabBarContainerShape
                            .fill(Color.secondary.opacity(0.065))
                    )
                    .overlay(
                        fileTabBarContainerShape
                            .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(fileTabBarContainerShape)
                    .padding(.leading, tabBarLeadingPadding)
                    .padding(.trailing, 10)
                    .padding(.vertical, 6)
                    .background(fileTabBarOffsetReader)
            }
            .onChange(of: viewModel.selectedTabID) { _, selectedTabID in
                guard let selectedTabID else { return }
                proxy.scrollTo(selectedTabID)
            }
        }
        .coordinateSpace(name: fileTabBarCoordinateSpaceName)
        .onPreferenceChange(FileTabBarContentMinXPreferenceKey.self) { minX in
            let isScrolled = minX < tabBarLeadingPadding - 1
            if fileTabBarIsScrolledUnderTOCEdge != isScrolled {
                fileTabBarIsScrolledUnderTOCEdge = isScrolled
            }
        }
        .modifier(FileTabBarScrollFadeMask(mask: fileTabBarScrollMask))
    }

#if os(macOS)
    private var macLegacyFileTabBar: some View {
        fileTabBarContent
            .padding(5)
            .background(
                fileTabBarContainerShape
                    .fill(Color.secondary.opacity(0.065))
            )
            .overlay(
                fileTabBarContainerShape
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )
            .clipShape(fileTabBarContainerShape)
            .padding(.leading, tabBarLeadingPadding)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                if fileTabBarIsScrolledUnderTOCEdge {
                    fileTabBarIsScrolledUnderTOCEdge = false
                }
            }
    }
#endif

    private var fileTabBarContent: some View {
        HStack(spacing: 6) {
            if viewModel.tabs.isEmpty {
                emptyFileTabButton
            } else {
                ForEach(viewModel.tabs) { tab in
                    fileTabItem(for: tab)
                        .id(tab.id)
                }
            }
        }
    }

    private var emptyFileTabButton: some View {
        Button {
            viewModel.addNewTab()
        } label: {
            HStack(spacing: 6) {
                Text("Untitled 1")
                    .lineLimit(1)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NeonUIStyle.accentBlue)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }

    private func fileTabItem(for tab: TabData) -> some View {
        let isSelected = viewModel.selectedTabID == tab.id
        let wasPreviouslySelected = previousSelectedTabID == tab.id && !isSelected
        let isDropTarget = tabDropInsertionTabID == tab.id
        return HStack(spacing: 8) {
            fileTabSelectButton(for: tab, isSelected: isSelected)
            fileTabCloseButton(for: tab)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
        )
        .overlay(alignment: isDropTarget && !tabDropInsertionBefore ? .trailing : .leading) {
#if os(macOS)
            if isSelected || wasPreviouslySelected || isDropTarget {
                Capsule()
                    .fill(isDropTarget || isSelected ? Color.accentColor : Color.yellow)
                    .frame(width: 3)
                    .padding(.vertical, 3)
                    .accessibilityHidden(true)
            }
#endif
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
#if os(macOS)
        .onTapGesture {
            viewModel.selectTab(id: tab.id)
        }
        .onTapGesture(count: 2) {
            requestCloseTab(tab)
        }
        .draggable(tab.id.uuidString)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .contentShape(Rectangle())
                    .onDrop(
                        of: [UTType.plainText.identifier],
                        delegate: FileTabDropDelegate(
                            destinationTabID: tab.id,
                            tabWidth: proxy.size.width,
                            insertionTabID: $tabDropInsertionTabID,
                            insertionBefore: $tabDropInsertionBefore,
                            moveTab: reorderDroppedTab
                        )
                    )
            }
        }
        .accessibilityHint(isSelected
            ? "Selected. Drag this tab onto the left or right half of another tab to reorder tabs."
            : "Drag onto the left or right half of another tab to reorder tabs.")
#endif
    }

#if os(macOS)
    private func reorderDroppedTab(
        draggedTabID: UUID,
        destinationTabID: UUID,
        insertBefore: Bool
    ) {
        guard draggedTabID != destinationTabID else { return }
        if insertBefore {
            viewModel.moveTab(tabID: draggedTabID, beforeTabID: destinationTabID)
        } else {
            viewModel.moveTab(tabID: draggedTabID, afterTabID: destinationTabID)
        }
        tabDropInsertionTabID = nil
    }
#endif

    private func fileTabSelectButton(for tab: TabData, isSelected: Bool) -> some View {
        Button {
            viewModel.selectTab(id: tab.id)
        } label: {
            fileTabTitleContent(for: tab, isSelected: isSelected)
                .padding(.leading, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tabAccessibilityLabel(for: tab))
        .accessibilityHint("Selects this editor tab.")
#if os(macOS)
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded { requestCloseTab(tab) }
        )
#endif
    }

    private func fileTabTitleContent(for tab: TabData, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            tabRemoteBadge(for: tab)
            Text(tab.name + (tab.isDirty ? " •" : ""))
                .lineLimit(1)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            if tab.isReadOnlyPreview {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func fileTabCloseButton(for tab: TabData) -> some View {
        Button {
            requestCloseTab(tab)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .padding(.trailing, 10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Close \(tab.name)")
    }

    private var usesSubtleTOCTransition: Bool {
#if os(macOS)
        usesTOCSplitChromeCleanup && fileTabBarIsScrolledUnderTOCEdge
#else
        false
#endif
    }

    private var usesMarkdownPreviewTabTransition: Bool {
        isMarkdownPreviewSplitVisible
    }

#if os(macOS)
    private var usesProjectSidebarTabTransition: Bool {
        showProjectStructureSidebar && projectNavigatorPlacement == .trailing && !brainDumpLayoutEnabled
    }

    private var usesTrailingTabTransition: Bool {
        usesMarkdownPreviewTabTransition || usesProjectSidebarTabTransition
    }

    private var usesAnySidebarTabTransition: Bool {
        usesSubtleTOCTransition || usesProjectSidebarTabTransition
    }

    private var usesTOCSplitChromeCleanup: Bool {
        shouldUseSplitView
    }
#else
    private var usesTrailingTabTransition: Bool {
        usesMarkdownPreviewTabTransition
    }
#endif

    private var fileTabBarCoordinateSpaceName: String {
        "FileTabBarScroll"
    }

    private var fileTabBarOffsetReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: FileTabBarContentMinXPreferenceKey.self,
                value: proxy.frame(in: .named(fileTabBarCoordinateSpaceName)).minX
            )
        }
    }

    @ViewBuilder
    private var fileTabBarScrollMask: some View {
        if usesSubtleTOCTransition || usesTrailingTabTransition {
            LinearGradient(
                stops: [
                    .init(color: usesSubtleTOCTransition ? .clear : .black, location: 0),
                    .init(color: .black, location: 0.035),
                    .init(color: .black, location: 0.965),
                    .init(color: usesTrailingTabTransition ? .clear : .black, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }

#if os(macOS)
    @ViewBuilder
    private var tabBarBottomDivider: some View {
        if usesAnySidebarTabTransition {
            Divider()
                .opacity(0.22)
                .padding(.leading, 18)
                .padding(.trailing, usesTrailingTabTransition ? 18 : 0)
        } else {
            Divider()
                .opacity(0.45)
        }
    }
#endif

    private var fileTabBarContainerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var vimStatusSuffix: String {
#if os(macOS)
        guard vimModeEnabled else { return " • Vim: OFF" }
        return vimInsertMode ? " • Vim: INSERT" : " • Vim: NORMAL"
#else
        guard UIDevice.current.userInterfaceIdiom == .pad else { return "" }
        guard vimModeEnabled else { return " • Vim: OFF" }
        return vimInsertMode ? " • Vim: INSERT" : " • Vim: NORMAL"
#endif
    }

    var importProgressPercentText: String {
        let clamped = min(max(droppedFileLoadProgress, 0), 1)
        if clamped > 0, clamped < 0.01 { return "1%" }
        return "\(Int(clamped * 100))%"
    }
}

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

private struct FileTabBarContentMinXPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension ContentView {
#if os(iOS)
    @ViewBuilder
    var iPhoneUnifiedTopChromeHost: some View {
        VStack(spacing: 0) {
            iPhoneUnifiedToolbarRow
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            tabBarView
        }
        .background(
            enableTranslucentWindow
            ? AnyShapeStyle(.ultraThinMaterial)
            : AnyShapeStyle(iOSNonTranslucentSurfaceColor)
        )
    }

    private var floatingStatusPillText: String {
        let base = effectiveLargeFileModeEnabled
            ? "\(caretStatus) • Lines: \(statusLineCount)\(vimStatusSuffix)"
            : "\(caretStatus) • Lines: \(statusLineCount) • Words: \(statusWordCount)\(vimStatusSuffix)"
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
        .accessibilityLabel("Editor status")
        .accessibilityValue(floatingStatusPillText)
    }

    private var iOSToolbarForegroundColor: Color {
        if toolbarIconsBlueIOS {
            return NeonUIStyle.accentBlue
        }
        return colorScheme == .dark ? Color.white.opacity(0.95) : Color.primary.opacity(0.92)
    }
#endif

    @ViewBuilder
    var wordCountView: some View {
        HStack(spacing: 10) {
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
                    Text("Deferred").tag("deferred")
                    Text("Plain Text").tag("plainText")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 280)
                .fixedSize(horizontal: false, vertical: true)
                .controlSize(.small)
                .accessibilityLabel("Large file open mode")
                .accessibilityHint("Choose how large files are opened and rendered")
            }
            if !remoteSessionStatusBadgeText.isEmpty {
                remoteSessionBadge
            }
            if !selectedRemoteDocumentBadgeText.isEmpty {
                selectedRemoteDocumentBadge
            }
            Spacer()
            Text(effectiveLargeFileModeEnabled
                 ? "\(caretStatus) • Lines: \(statusLineCount)\(vimStatusSuffix)"
                 : "\(caretStatus) • Lines: \(statusLineCount) • Words: \(statusWordCount)\(vimStatusSuffix)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
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
        .accessibilityHint("Open large file mode options")
    }

    @ViewBuilder
    private var largeFileOpenModeMenuContent: some View {
        Button {
            largeFileOpenModeRaw = "standard"
        } label: {
            largeFileOpenModeMenuLabel(title: "Standard", isSelected: largeFileOpenModeRaw == "standard")
        }
        Button {
            largeFileOpenModeRaw = "deferred"
        } label: {
            largeFileOpenModeMenuLabel(title: "Deferred", isSelected: largeFileOpenModeRaw == "deferred")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if viewModel.tabs.isEmpty {
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
                    } else {
                        ForEach(viewModel.tabs) { tab in
                            fileTabItem(for: tab)
                        }
                    }
                }
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
            .coordinateSpace(name: fileTabBarCoordinateSpaceName)
            .onPreferenceChange(FileTabBarContentMinXPreferenceKey.self) { minX in
                let isScrolled = minX < tabBarLeadingPadding - 1
                if fileTabBarIsScrolledUnderTOCEdge != isScrolled {
                    fileTabBarIsScrolledUnderTOCEdge = isScrolled
                }
            }
            .mask(fileTabBarScrollMask)
#if os(iOS)
            EmptyView()
#else
            tabBarBottomDivider
#endif
        }
        .frame(minHeight: 42, maxHeight: 42, alignment: .center)
#if os(macOS)
        .background(editorSurfaceBackgroundStyle.opacity(usesSubtleTOCTransition ? 0 : 1))
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

    private func fileTabItem(for tab: TabData) -> some View {
        let isSelected = viewModel.selectedTabID == tab.id
        return HStack(spacing: 8) {
            fileTabSelectButton(for: tab, isSelected: isSelected)
            fileTabCloseButton(for: tab)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
        )
    }

    private func fileTabSelectButton(for tab: TabData, isSelected: Bool) -> some View {
        Button {
            viewModel.selectTab(id: tab.id)
        } label: {
            fileTabTitleContent(for: tab, isSelected: isSelected)
                .padding(.leading, 10)
                .padding(.vertical, 6)
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
    private var usesTOCSplitChromeCleanup: Bool {
        shouldUseSplitView
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
        if usesSubtleTOCTransition || usesMarkdownPreviewTabTransition {
            LinearGradient(
                stops: [
                    .init(color: usesSubtleTOCTransition ? .clear : .black, location: 0),
                    .init(color: .black, location: 0.035),
                    .init(color: .black, location: 0.965),
                    .init(color: usesMarkdownPreviewTabTransition ? .clear : .black, location: 1)
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
        if viewModel.showSidebar && !brainDumpLayoutEnabled {
            Divider()
                .opacity(0.22)
                .padding(.leading, 18)
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

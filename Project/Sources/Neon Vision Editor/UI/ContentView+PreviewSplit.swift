import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if os(macOS)
enum PreviewPaneResizeGeometry {
    static func width(
        startWidth: CGFloat,
        translation: CGFloat,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat
    ) -> CGFloat {
        min(max(startWidth - translation, minimumWidth), maximumWidth)
    }
}
#endif

enum MarkdownPreviewOpenMode: String, CaseIterable, Identifiable {
    case edit
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edit: return "Editor"
        case .preview: return "Preview"
        }
    }

    var previewMode: ContentView.PreviewMode {
        self == .preview ? .markdown : .none
    }

    var presentsAsReadingView: Bool {
        self == .preview
    }
}

enum MarkdownPreviewPresentationPolicy {
    static func showsReadingView(
        isReadingMode: Bool,
        isMarkdownDocument: Bool,
        isPreviewActive: Bool,
        isSafeMode: Bool,
        isBrainDumpLayout: Bool,
        isFocusMode: Bool
    ) -> Bool {
        isReadingMode && isMarkdownDocument && isPreviewActive &&
        !isSafeMode && !isBrainDumpLayout && !isFocusMode
    }

    static func showsSplitPane(
        canShowPane: Bool,
        isMarkdownDocument: Bool,
        isPreviewActive: Bool,
        readingViewVisible: Bool,
        isSafeMode: Bool,
        isBrainDumpLayout: Bool,
        isFocusMode: Bool
    ) -> Bool {
        canShowPane && isMarkdownDocument && isPreviewActive && !readingViewVisible &&
        !isSafeMode && !isBrainDumpLayout && !isFocusMode
    }
}

// MARK: - Preview Split Coordination

struct PreviewPaneHeader<Actions: View>: View {
    let title: String
    let iconName: String
    let metadata: String?
    let backgroundStyle: AnyShapeStyle
    let onClose: (() -> Void)?
    let actions: Actions

    init(
        title: String,
        iconName: String,
        metadata: String?,
        backgroundStyle: AnyShapeStyle,
        onClose: (() -> Void)? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.iconName = iconName
        self.metadata = metadata
        self.backgroundStyle = backgroundStyle
        self.onClose = onClose
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let metadata {
                Text(metadata)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            actions
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(backgroundStyle)
    }
}

extension ContentView {
#if os(macOS)
    func applyDefaultMarkdownPreviewOpenMode() {
        guard isMarkdownPreviewDocument else {
            isMarkdownPreviewReadingMode = false
            return
        }
        let openMode = MarkdownPreviewOpenMode(rawValue: markdownPreviewDefaultModeRaw) ?? .edit
        previewMode = openMode.previewMode
        isMarkdownPreviewReadingMode = openMode.presentsAsReadingView
    }
#endif

    var isMarkdownPreviewReadingViewVisible: Bool {
#if os(macOS)
        MarkdownPreviewPresentationPolicy.showsReadingView(
            isReadingMode: isMarkdownPreviewReadingMode,
            isMarkdownDocument: isMarkdownPreviewDocument,
            isPreviewActive: previewMode == .markdown,
            isSafeMode: isSafeModeActive,
            isBrainDumpLayout: brainDumpLayoutEnabled,
            isFocusMode: focusModeEnabled
        )
#else
        false
#endif
    }

    func previewPaneHeader<Actions: View>(
        title: String,
        iconName: String,
        metadata: String?,
        onClose: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        PreviewPaneHeader(
            title: viewModel.selectedTab == nil ? title : previewDocumentTitle,
            iconName: iconName,
            metadata: metadata,
            backgroundStyle: editorSurfaceBackgroundStyle,
            onClose: onClose
        ) {
            actions()
        }
    }

    /// Opens previews for binary documents regardless of whether the tab was
    /// created by the toolbar, Launch Services, paste/drop, or session restore.
    /// This only changes the mode when the current document has a native binary
    /// preview, so text and Markdown preview behavior remains user-controlled.
    func openAutomaticPreviewIfNeeded() {
        guard let automaticPreviewMode = automaticPreviewModeForCurrentDocument else { return }
        guard previewMode != automaticPreviewMode else { return }
        previewMode = automaticPreviewMode
    }

    var isMarkdownPreviewDocument: Bool {
        let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn", "mdx"]
        if let pathExtension = viewModel.selectedTab?.fileURL?.pathExtension.lowercased(),
           markdownExtensions.contains(pathExtension) {
            return true
        }
        return currentLanguage.lowercased() == "markdown"
    }

    var isSVGDocument: Bool {
        if viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "svg" {
            return true
        }
        let lowerLanguage = currentLanguage.lowercased()
        guard lowerLanguage == "xml" || lowerLanguage == "svg" else { return false }
        let sample = currentDocumentPrefix(maxUTF16Length: 1_024).lowercased()
        return sample.contains("<svg")
    }

    var isHTMLPreviewDocument: Bool {
        if let pathExtension = viewModel.selectedTab?.fileURL?.pathExtension.lowercased(),
           pathExtension == "html" || pathExtension == "htm" || pathExtension == "xhtml" {
            return true
        }
        let lowerLanguage = currentLanguage.lowercased()
        return lowerLanguage == "html" || lowerLanguage == "xhtml"
    }

    var isPNGPreviewDocument: Bool {
        viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "png"
    }

    var isPDFPreviewDocument: Bool {
        if isPDFNoteEditorActive { return true }
        return viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "pdf"
    }

    var pdfPreviewURL: URL? {
        if isPDFNoteEditorActive {
            return pdfNoteSourceURL
        }
        guard viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "pdf" else { return nil }
        return viewModel.selectedTab?.fileURL
    }

    var isPDFNoteEditorActive: Bool {
        pdfNoteSourceURL != nil && pdfNoteTabID == viewModel.selectedTabID
    }

    var isPreviewSupportedDocument: Bool {
        previewModeForCurrentDocument != nil
    }

    var previewModeForCurrentDocument: PreviewMode? {
        if isJSONPreviewDocument { return .json }
        if isYAMLPreviewDocument { return .yaml }
        if isMarkdownPreviewDocument { return .markdown }
        if isSVGDocument || isHTMLPreviewDocument { return .web }
        if isPNGPreviewDocument { return .image }
        if isPDFPreviewDocument { return .pdf }
        return nil
    }

    var automaticPreviewModeForCurrentDocument: PreviewMode? {
        if isPNGPreviewDocument { return .image }
        if isPDFPreviewDocument { return .pdf }
        return nil
    }

    // Compatibility accessors keep the individual preview views declarative while
    // previewMode remains the single source of truth for toolbar transitions.
    var showMarkdownPreviewPane: Bool {
        get { previewMode == .markdown }
        nonmutating set {
            if newValue {
                previewMode = .markdown
            } else if previewMode == .markdown {
                previewMode = .none
            }
        }
    }

    var showWebPreviewPane: Bool {
        get { previewMode == .web }
        nonmutating set {
            if newValue {
                previewMode = .web
            } else if previewMode == .web {
                previewMode = .none
            }
        }
    }

    /// A stale restored mode is not considered visible for another document type.
    var isPreviewVisible: Bool {
        previewMode == previewModeForCurrentDocument
    }

    var previewDocumentTitle: String {
        let fileURL = previewMode == .pdf ? pdfPreviewURL : viewModel.selectedTab?.fileURL
        return fileURL?.lastPathComponent ?? viewModel.selectedTab?.name ?? previewTitle
    }

    var previewTitle: String {
        if isJSONPreviewDocument { return "JSON Preview" }
        if isYAMLPreviewDocument { return "YAML Preview" }
        if isSVGDocument { return "SVG Preview" }
        if isHTMLPreviewDocument { return "HTML Preview" }
        if isPNGPreviewDocument { return "PNG Preview" }
        if isPDFPreviewDocument { return "PDF Preview" }
        return "Markdown Preview"
    }

    var previewToolbarIconName: String {
        isPreviewVisible ? "eye.fill" : "eye"
    }

#if os(macOS)
    var detachedPreviewHTML: String {
        if isMarkdownPreviewDocument {
            return markdownPreviewRenderedHTML.isEmpty
                ? markdownPreviewLoadingHTML(preferDarkMode: markdownPreviewPreferDarkMode)
                : markdownPreviewRenderedHTML
        }
        return webPreviewHTML(from: currentContent)
    }

    var detachedPreviewBaseURL: URL? {
        return isMarkdownPreviewDocument ? localPreviewBaseURL : localWebPreviewBaseURL
    }
#endif

    var canShowMarkdownPreviewPane: Bool { true }

    var isJSONPreviewDocument: Bool {
        viewModel.selectedTab?.fileURL?.pathExtension.lowercased() == "json" || currentLanguage.lowercased() == "json"
    }

    var isJSONPreviewSplitVisible: Bool {
        canShowMarkdownPreviewSplitPane && previewMode == .json && isJSONPreviewDocument &&
        !isSafeModeActive && !brainDumpLayoutEnabled && !focusModeEnabled
    }

    var jsonPreviewSplitPane: some View {
        previewSplitPane { jsonPreviewPane }
    }

    var isYAMLPreviewDocument: Bool {
        YAMLPreviewDocument.supports(extension: viewModel.selectedTab?.fileURL?.pathExtension, language: currentLanguage)
    }

    var isYAMLPreviewSplitVisible: Bool {
        canShowMarkdownPreviewSplitPane && previewMode == .yaml && isYAMLPreviewDocument &&
        !isSafeModeActive && !brainDumpLayoutEnabled && !focusModeEnabled
    }

    var yamlPreviewSplitPane: some View {
        previewSplitPane { yamlPreviewPane }
    }

    var isMarkdownPreviewSplitVisible: Bool {
        MarkdownPreviewPresentationPolicy.showsSplitPane(
            canShowPane: canShowMarkdownPreviewSplitPane,
            isMarkdownDocument: isMarkdownPreviewDocument,
            isPreviewActive: showMarkdownPreviewPane,
            readingViewVisible: isMarkdownPreviewReadingViewVisible,
            isSafeMode: isSafeModeActive,
            isBrainDumpLayout: brainDumpLayoutEnabled,
            isFocusMode: focusModeEnabled
        )
    }

    var isWebPreviewSplitVisible: Bool {
        canShowWebPreviewSplitPane &&
        showWebPreviewPane &&
        (isSVGDocument || isHTMLPreviewDocument) &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled &&
        !focusModeEnabled
    }

    var isImagePreviewSplitVisible: Bool {
        canShowImagePreviewSplitPane &&
        previewMode == .image &&
        isPNGPreviewDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled &&
        !focusModeEnabled
    }

    var isPDFPreviewSplitVisible: Bool {
        canShowPDFPreviewSplitPane &&
        previewMode == .pdf &&
        isPDFPreviewDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled &&
        !focusModeEnabled
    }

#if os(iOS) || os(visionOS)
    var previewSheetPresentationBinding: Binding<Bool> {
        Binding(
            get: { shouldPresentPreviewSheetOnIPhone },
            set: { isPresented in
                if !isPresented {
                    closeCurrentPreview()
                }
            }
        )
    }
#endif

    @ViewBuilder
    var markdownPreviewSplitPane: some View {
        previewSplitPane {
            markdownPreviewPane
        }
    }

    @ViewBuilder
    var webPreviewSplitPane: some View {
        previewSplitPane {
            webPreviewPane
        }
    }

    @ViewBuilder
    var imagePreviewSplitPane: some View {
        previewSplitPane {
            imagePreviewPane
        }
    }

    @ViewBuilder
    var pdfPreviewSplitPane: some View {
        previewSplitPane {
            if isPDFNoteMarkdownPreviewVisible, pdfNoteTabID != nil {
                HStack(spacing: 0) {
                    pdfPreviewPane
                    markdownPreviewPane
                }
            } else {
                pdfPreviewPane
            }
        }
    }

    private var canShowMarkdownPreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

    private var canShowWebPreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

    private var canShowImagePreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

    private var canShowPDFPreviewSplitPane: Bool {
#if os(iOS) || os(visionOS)
        canShowPreviewOnCurrentDevice
#else
        true
#endif
    }

#if os(iOS) || os(visionOS)
    private var canShowPreviewOnCurrentDevice: Bool {
        usesRegularIOSLayout
    }

    private var shouldPresentPreviewSheetOnIPhone: Bool {
        usesCompactIOSLayout &&
        isPreviewVisible &&
        isPreviewSupportedDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }
#endif

    @ViewBuilder
    private func previewSplitPane<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
#if os(macOS)
            .frame(minWidth: 280, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
#else
            .frame(minWidth: 280, idealWidth: 420, maxWidth: 680, maxHeight: .infinity)
#endif
            .background(editorSurfaceBackgroundStyle)
            .clipShape(previewSplitPaneShape)
#if !os(macOS)
            .overlay {
                previewSplitPaneShape
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
#endif
            .padding(.top, 4)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
    }

#if os(macOS)
    var minimumPreviewPaneWidth: CGFloat { 280 }
    var minimumEditorPaneWidth: CGFloat { 320 }
    var previewPaneResizeHandleWidth: CGFloat { 11 }
    var previewPaneResizeHitTargetWidth: CGFloat { macOSResizeHitTargetWidth }

    var defaultPreviewPaneWidth: CGFloat {
        guard previewPaneAvailableWidth > 0 else { return 420 }
        return max(
            minimumPreviewPaneWidth,
            (previewPaneAvailableWidth - previewPaneResizeHandleWidth - markdownProjectPreviewReservedWidth) / 2
        )
    }

    var maximumPreviewPaneWidth: CGFloat {
        guard previewPaneAvailableWidth > 0 else { return 960 }
        return max(
            minimumPreviewPaneWidth,
            previewPaneAvailableWidth - minimumEditorPaneWidth - previewPaneResizeHandleWidth - markdownProjectPreviewReservedWidth
        )
    }

    var clampedPreviewPaneWidth: CGFloat {
        let requestedWidth = previewPaneWidth > 0
            ? CGFloat(previewPaneWidth)
            : defaultPreviewPaneWidth
        return min(max(requestedWidth, minimumPreviewPaneWidth), maximumPreviewPaneWidth)
    }

    var previewPaneResizeHandle: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startWidth = previewPaneResizeStartWidth ?? clampedPreviewPaneWidth
                if previewPaneResizeStartWidth == nil {
                    previewPaneResizeStartWidth = startWidth
                    // The parent geometry changes as this divider moves. Keep
                    // its constraint stable for this gesture so the divider
                    // follows the pointer instead of feeding layout changes
                    // back into the active drag.
                    previewPaneResizeMaximumWidth = maximumPreviewPaneWidth
                }
                let clamped = PreviewPaneResizeGeometry.width(
                    startWidth: startWidth,
                    translation: value.translation.width,
                    minimumWidth: minimumPreviewPaneWidth,
                    maximumWidth: previewPaneResizeMaximumWidth ?? maximumPreviewPaneWidth
                )
                previewPaneWidth = Double(clamped)
            }
            .onEnded { _ in
                previewPaneWidth = Double(clampedPreviewPaneWidth)
                previewPaneResizeStartWidth = nil
                previewPaneResizeMaximumWidth = nil
                isPreviewPaneResizeHandleHovered = false
                MacSidebarResizeCursor.reset(ownerID: "preview-pane")
            }

        return MacSidebarResizeDivider(
            visibleWidth: previewPaneResizeHandleWidth,
            hitTargetWidth: previewPaneResizeHitTargetWidth,
            cursorOwnerID: "preview-pane",
            accentWidth: isPreviewPaneResizeHandleHovered || previewPaneResizeStartWidth != nil ? 2 : 0,
            accentColor: Color.accentColor.opacity(0.55),
            surfaceStyle: macResizeHandleSurfaceStyle,
            topSurfaceStyle: macToolbarBackgroundStyle,
            isActive: isPreviewPaneResizeHandleHovered || previewPaneResizeStartWidth != nil,
            isDragging: previewPaneResizeStartWidth != nil,
            isHovered: $isPreviewPaneResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Preview",
            accessibilityHint: "Drag left or right to adjust preview width",
            accessibilityAdjust: { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                let adjusted = min(
                    max(clampedPreviewPaneWidth + delta, minimumPreviewPaneWidth),
                    maximumPreviewPaneWidth
                )
                previewPaneWidth = Double(adjusted)
            }
        )
    }
#endif

    private var previewSplitPaneShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 10,
            topTrailingRadius: 16,
            style: .continuous
        )
    }
}

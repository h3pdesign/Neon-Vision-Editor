import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Preview Split Coordination

extension ContentView {
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
        let sample = currentContent.prefix(1024).lowercased()
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

    var previewTitle: String {
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

    var isMarkdownPreviewSplitVisible: Bool {
        canShowMarkdownPreviewSplitPane &&
        showMarkdownPreviewPane &&
        isMarkdownPreviewDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

    var isWebPreviewSplitVisible: Bool {
        canShowWebPreviewSplitPane &&
        showWebPreviewPane &&
        (isSVGDocument || isHTMLPreviewDocument) &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

    var isImagePreviewSplitVisible: Bool {
        canShowImagePreviewSplitPane &&
        previewMode == .image &&
        isPNGPreviewDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

    var isPDFPreviewSplitVisible: Bool {
        canShowPDFPreviewSplitPane &&
        previewMode == .pdf &&
        isPDFPreviewDocument &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
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
        horizontalSizeClass == .regular
    }

    private var shouldPresentPreviewSheetOnIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone &&
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
                }
                let proposed = startWidth - value.translation.width
                let clamped = min(max(proposed, minimumPreviewPaneWidth), maximumPreviewPaneWidth)
                previewPaneWidth = Double(clamped)
            }
            .onEnded { _ in
                previewPaneResizeStartWidth = nil
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

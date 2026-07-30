import SwiftUI

extension ContentView {
    var markdownProjectPreviewMode: MarkdownProjectPreviewMode {
        get { MarkdownProjectPreviewMode(rawValue: markdownProjectPreviewModeRaw) ?? .grid }
        nonmutating set { markdownProjectPreviewModeRaw = newValue.rawValue }
    }

    var markdownProjectPreviewPlacement: MarkdownProjectPreviewPlacement {
        MarkdownProjectPreviewPlacement(rawValue: markdownProjectPreviewPlacementRaw) ?? .trailing
    }

    var markdownProjectPreviewSortOrder: MarkdownProjectPreviewSortOrder {
        get { MarkdownProjectPreviewSortOrder(rawValue: markdownProjectPreviewSortOrderRaw) ?? .name }
        nonmutating set {
            markdownProjectPreviewSortOrderRaw = newValue.rawValue
            markdownProjectPreviewModel.setSortOrder(newValue)
        }
    }

    var isMarkdownProjectPreviewVisible: Bool {
        markdownProjectPreviewEnabled &&
        isMarkdownProjectPreviewPresented &&
        projectRootFolderURL != nil &&
        !isSafeModeActive &&
        !brainDumpLayoutEnabled
    }

    var markdownProjectPreviewIndexSignature: String {
        projectFileIndexSnapshot.entries
            .filter { entry in
                ["md", "markdown", "mdown", "mkdn", "mdx"].contains(entry.url.pathExtension.lowercased())
            }
            .map { entry in
                "\(entry.standardizedPath)|\(entry.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1)|\(entry.fileSize ?? -1)"
            }
            .joined(separator: "\n")
    }

    func refreshMarkdownProjectPreview() {
        guard projectRootFolderURL != nil, projectFileIndexHasCompleted else {
            markdownProjectPreviewModel.cancel()
            return
        }
        markdownProjectPreviewModel.setSortOrder(markdownProjectPreviewSortOrder)
        markdownProjectPreviewModel.refresh(
            entries: projectFileIndexSnapshot.entries,
            projectRoot: projectRootFolderURL
        )
    }

    func openMarkdownProjectPreviewFile(_ url: URL) {
        _ = viewModel.openFile(url: url)
#if os(iOS)
        // The card browser is presented as a sheet on iPhone. Dismiss it after
        // selecting the file so the user lands directly in the editor.
        isMarkdownProjectPreviewPresented = false
#endif
    }

    private var markdownProjectPreviewCurrentURL: URL? {
#if os(iOS)
        // The compact card browser is a sheet rather than the split preview,
        // so the selected editor tab is the persistent marker source while
        // the sheet is open.
        return viewModel.selectedTab?.fileURL
#else
        return isMarkdownPreviewSplitVisible ? viewModel.selectedTab?.fileURL : nil
#endif
    }

    @ViewBuilder
    var markdownProjectPreviewPanel: some View {
        MarkdownProjectPreviewPanel(
            cards: markdownProjectPreviewModel.cards,
            currentPreviewURL: markdownProjectPreviewCurrentURL,
            isIndexing: isProjectFileIndexing,
            isIndexReady: projectFileIndexHasCompleted,
            indexedFileCount: projectFileIndexSnapshot.entries.count,
            isPreparingPreviews: markdownProjectPreviewModel.isLoading,
            previewStatus: markdownProjectPreviewModel.loadingStatus,
            mode: Binding(
                get: { markdownProjectPreviewMode },
                set: { markdownProjectPreviewMode = $0 }
            ),
            sortOrder: Binding(
                get: { markdownProjectPreviewSortOrder },
                set: { markdownProjectPreviewSortOrder = $0 }
            ),
            onOpen: openMarkdownProjectPreviewFile,
            onReveal: revealProjectItem,
            onRefresh: refreshMarkdownProjectPreview
        )
        .background(editorSurfaceBackgroundStyle)
    }

    var clampedMarkdownProjectPreviewWidthIfAvailable: CGFloat {
#if os(macOS)
        clampedMarkdownProjectPreviewWidth
#else
        300
#endif
    }

#if os(macOS)
    var minimumMarkdownProjectPreviewWidth: CGFloat { 260 }
    var maximumMarkdownProjectPreviewWidth: CGFloat {
        guard previewPaneAvailableWidth > 0 else { return 520 }
        let previewReservation = (isMarkdownPreviewSplitVisible || isWebPreviewSplitVisible)
            ? previewPaneResizeHandleWidth + minimumPreviewPaneWidth
            : 0
        let available = previewPaneAvailableWidth
            - minimumEditorPaneWidth
            - previewReservation
            - macOSResizeHitTargetWidth
        return max(minimumMarkdownProjectPreviewWidth, min(520, available))
    }

    var clampedMarkdownProjectPreviewWidth: CGFloat {
        min(
            max(CGFloat(markdownProjectPreviewWidth), minimumMarkdownProjectPreviewWidth),
            maximumMarkdownProjectPreviewWidth
        )
    }

    var markdownProjectPreviewReservedWidth: CGFloat {
        isMarkdownProjectPreviewVisible
            ? clampedMarkdownProjectPreviewWidth + macOSResizeHitTargetWidth
            : 0
    }

    var markdownProjectPreviewResizeHandle: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startWidth = markdownProjectPreviewResizeStartWidth ?? clampedMarkdownProjectPreviewWidth
                if markdownProjectPreviewResizeStartWidth == nil {
                    markdownProjectPreviewResizeStartWidth = startWidth
                }
                let proposed = markdownProjectPreviewPlacement == .trailing
                    ? startWidth - value.translation.width
                    : startWidth + value.translation.width
                markdownProjectPreviewWidth = Double(min(max(proposed, minimumMarkdownProjectPreviewWidth), maximumMarkdownProjectPreviewWidth))
            }
            .onEnded { _ in
                markdownProjectPreviewResizeStartWidth = nil
                isMarkdownProjectPreviewResizeHandleHovered = false
                MacSidebarResizeCursor.reset(ownerID: "markdown-project-preview")
            }

        return MacSidebarResizeDivider(
            visibleWidth: macOSResizeHitTargetWidth,
            hitTargetWidth: macOSResizeHitTargetWidth,
            cursorOwnerID: "markdown-project-preview",
            accentWidth: isMarkdownProjectPreviewResizeHandleHovered || markdownProjectPreviewResizeStartWidth != nil ? 2 : 0,
            accentColor: Color.accentColor.opacity(0.55),
            surfaceStyle: macResizeHandleSurfaceStyle,
            isActive: isMarkdownProjectPreviewResizeHandleHovered || markdownProjectPreviewResizeStartWidth != nil,
            isDragging: markdownProjectPreviewResizeStartWidth != nil,
            isHovered: $isMarkdownProjectPreviewResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Markdown project preview",
            accessibilityHint: "Drag left or right to adjust the Markdown card panel width",
            accessibilityAdjust: { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                markdownProjectPreviewWidth = Double(min(max(clampedMarkdownProjectPreviewWidth + delta, minimumMarkdownProjectPreviewWidth), maximumMarkdownProjectPreviewWidth))
            }
        )
    }
#endif
}

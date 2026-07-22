import SwiftUI

#if os(macOS)
import AppKit
#endif

extension ContentView {
    @ViewBuilder
    var projectStructureSidebarPanel: some View {
#if os(macOS)
        projectStructureSidebarBody
            .frame(
                minWidth: clampedProjectSidebarWidth,
                idealWidth: clampedProjectSidebarWidth,
                maxWidth: clampedProjectSidebarWidth
            )
            .background(editorSurfaceBackgroundStyle)
#else
        projectStructureSidebarBody
            .frame(
                minWidth: clampedProjectSidebarWidth,
                idealWidth: clampedProjectSidebarWidth,
                maxWidth: clampedProjectSidebarWidth
            )
            .background(editorSurfaceBackgroundStyle)
#endif
    }

    var projectSidebarResizeHandle: some View {
        let drag = DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startWidth = projectSidebarResizeStartWidth ?? clampedProjectSidebarWidth
                if projectSidebarResizeStartWidth == nil {
                    projectSidebarResizeStartWidth = startWidth
                }
                let delta = value.translation.width
                let proposed: CGFloat
                switch projectNavigatorPlacement {
                case .leading:
                    proposed = startWidth + delta
                case .trailing:
                    proposed = startWidth - delta
                }
                let clamped = min(max(proposed, minimumProjectSidebarWidth), maximumProjectSidebarWidth)
                projectSidebarWidth = Double(clamped)
            }
            .onEnded { _ in
                projectSidebarResizeStartWidth = nil
#if os(macOS)
                if !isProjectSidebarResizeHandleHovered {
                    MacSidebarResizeCursor.reset()
                }
#endif
            }

#if os(macOS)
        return MacSidebarResizeDivider(
            visibleWidth: projectSidebarResizeHandleWidth,
            hitTargetWidth: projectSidebarResizeHitTargetWidth,
            accentWidth: projectSidebarResizeHandleAccentWidth,
            accentColor: projectSidebarHandleAccentColor,
            surfaceStyle: projectSidebarHandleSurfaceStyle,
            isActive: projectSidebarResizeHandleIsActive,
            isDragging: projectSidebarResizeStartWidth != nil,
            isHovered: $isProjectSidebarResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Project Sidebar",
            accessibilityHint: "Drag left or right to adjust project sidebar width"
        )
#else
        return ZStack {
            Rectangle()
                .fill(Color.clear)
            Rectangle()
                .fill(projectSidebarHandleAccentColor)
                .frame(width: projectSidebarResizeHandleAccentWidth)
                .clipShape(Capsule())
                .padding(.vertical, projectSidebarResizeHandleIsActive ? 30 : 0)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: projectSidebarResizeHandleWidth)
        .background(projectSidebarHandleSurfaceStyle)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel("Resize Project Sidebar")
        .accessibilityHint("Drag left or right to adjust project sidebar width")
#endif
    }

    var projectSidebarHandleAccentColor: Color {
#if os(macOS)
        return Color.clear
#else
        let isActive = projectSidebarResizeHandleIsActive
        return isActive ? Color.accentColor.opacity(0.70) : projectSidebarHandleDividerColor
#endif
    }

    var projectSidebarResizeHandleAccentWidth: CGFloat {
#if os(macOS)
        0
#else
        projectSidebarResizeHandleIsActive ? 2.5 : 1.5
#endif
    }

    var projectSidebarHandleDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.30) : Color.black.opacity(0.22)
    }

    var projectSidebarResizeHandleIsActive: Bool {
#if os(macOS)
        isProjectSidebarResizeHandleHovered || projectSidebarResizeStartWidth != nil
#else
        projectSidebarResizeStartWidth != nil
#endif
    }

    var projectSidebarHandleSurfaceStyle: AnyShapeStyle {
#if os(macOS)
        return editorSurfaceBackgroundStyle
#else
        if enableTranslucentWindow {
            return editorSurfaceBackgroundStyle
        }
        return useIOSUnifiedSolidSurfaces
            ? AnyShapeStyle(iOSNonTranslucentSurfaceColor)
            : AnyShapeStyle(Color.clear)
#endif
    }

    var projectStructureSidebarBody: some View {
        ProjectStructureSidebarView(
            rootFolderURL: projectRootFolderURL,
            nodes: projectTreeNodes,
            selectedFileURL: viewModel.selectedTab?.fileURL,
            showSupportedFilesOnly: showSupportedProjectFilesOnly,
            showHiddenFiles: showHiddenProjectFiles,
            ignoredFolderNamesRaw: $projectIgnoredFolderNamesRaw,
            translucentBackgroundEnabled: enableTranslucentWindow,
            boundaryEdge: projectNavigatorPlacement == .leading ? .trailing : .leading,
            onOpenFile: { openFileFromToolbar() },
            onOpenFolder: { openProjectFolder() },
            onOpenProjectFolder: { setProjectFolder($0) },
            onToggleSupportedFilesOnly: { showSupportedProjectFilesOnly = $0 },
            onToggleHiddenFiles: { showHiddenProjectFiles = $0 },
            onOpenProjectFile: { url in
                Task { @MainActor in
                    openProjectFileFromProjectSidebar(url: url)
                }
            },
            onRefreshTree: { refreshProjectBrowserState(showsStatusFeedback: true) },
            onCreateProjectFile: { startProjectItemCreation(kind: .file, in: $0) },
            onCreateProjectFolder: { startProjectItemCreation(kind: .folder, in: $0) },
            onRenameProjectItem: { startProjectItemRename($0) },
            onDuplicateProjectItem: { duplicateProjectItem($0) },
            onDeleteProjectItem: { requestDeleteProjectItem($0) },
            onToggleGitTab: { showGitTab = true },
            onShowGitDiff: { title, leftTitle, rightTitle, leftContent, rightContent in
                presentGitDiff(
                    title: title,
                    leftTitle: leftTitle,
                    rightTitle: rightTitle,
                    leftContent: leftContent,
                    rightContent: rightContent
                )
            },
            findInFilesQuery: $findInFilesQuery,
            findInFilesCaseSensitive: $findInFilesCaseSensitive,
            findInFilesReplaceQuery: $findInFilesReplaceQuery,
            findInFilesSelectedMatchIDs: $findInFilesSelectedMatchIDs,
            findInFilesResults: findInFilesResults,
            findInFilesStatusMessage: findInFilesStatusMessage,
            findInFilesSourceMessage: findInFilesSourceMessage,
            isApplyingFindInFilesReplace: isApplyingFindInFilesReplace,
            onFindInFilesSearch: { startFindInFiles() },
            onFindInFilesClear: { clearFindInFiles() },
            onToggleFindInFilesSelection: { toggleFindInFilesMatchSelection($0) },
            onSelectAllFindInFilesMatches: { selectAllFindInFilesMatches() },
            onSelectNoFindInFilesMatches: { clearFindInFilesSelection() },
            onApplyFindInFilesReplace: { applyProjectWideReplaceFromFindInFiles() },
            onCancelFindInFilesReplace: { cancelProjectWideReplaceFromFindInFiles() },
            onSelectFindInFilesMatch: { selectFindInFilesMatch($0) },
            activateFindInFilesToken: projectSidebarFindInFilesRequestToken,
            activateTerminalToken: projectSidebarTerminalRequestToken,
            compareDiffPresentation: sidebarCompareDiffPresentation,
            onCloseCompareDiff: { sidebarCompareDiffPresentation = nil },
            revealURL: projectTreeRevealURL,
            gitFileStatusMap: gitViewModel.fileStatusMap,
            gitViewModel: gitViewModel
        )
    }

#if os(macOS)
    @MainActor
    func showTerminalInProjectSidebar() {
        showProjectStructureSidebar = true
        projectSidebarTerminalRequestToken &+= 1
    }
#endif
}

#if os(macOS)
enum MacSidebarResizeCursor {
    static func set() {
        NSCursor.resizeLeftRight.set()
    }

    static func reset() {
        NSCursor.arrow.set()
    }
}

struct MacSidebarResizeDivider<ResizeGesture: Gesture>: View where ResizeGesture.Value == DragGesture.Value {
    let visibleWidth: CGFloat
    let hitTargetWidth: CGFloat
    let accentWidth: CGFloat
    let accentColor: Color
    let surfaceStyle: AnyShapeStyle
    let isActive: Bool
    let isDragging: Bool
    @Binding var isHovered: Bool
    let drag: ResizeGesture
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)

            Rectangle()
                .fill(accentColor)
                .frame(width: accentWidth)
                .clipShape(Capsule())
                .padding(.vertical, isActive ? 26 : 8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: visibleWidth)
        .background(surfaceStyle)
        .overlay {
            MacSidebarResizeCursorTrackingView(isHovered: $isHovered, isDragging: isDragging)
                .frame(width: hitTargetWidth)
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .animation(.easeOut(duration: 0.12), value: isActive)
        .onDisappear {
            isHovered = false
            MacSidebarResizeCursor.reset()
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct MacSidebarResizeCursorTrackingView: NSViewRepresentable {
    @Binding var isHovered: Bool
    let isDragging: Bool

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = { hovering in
            isHovered = hovering
        }
        view.isDragging = isDragging
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = { hovering in
            isHovered = hovering
        }
        nsView.isDragging = isDragging
        if isDragging || isHovered {
            MacSidebarResizeCursor.set()
        }
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        var isDragging: Bool = false
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeInActiveApp,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
            MacSidebarResizeCursor.set()
        }

        override func mouseMoved(with event: NSEvent) {
            MacSidebarResizeCursor.set()
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
            if !isDragging {
                MacSidebarResizeCursor.reset()
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .resizeLeftRight)
        }
    }
}
#endif

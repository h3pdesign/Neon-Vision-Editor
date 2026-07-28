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
                isProjectSidebarResizeHandleHovered = false
#if os(macOS)
                MacSidebarResizeCursor.reset(ownerID: "project-sidebar")
#endif
            }

#if os(macOS)
        return MacSidebarResizeDivider(
            visibleWidth: projectSidebarResizeHandleWidth,
            hitTargetWidth: projectSidebarResizeHitTargetWidth,
            cursorOwnerID: "project-sidebar",
            accentWidth: projectSidebarResizeHandleAccentWidth,
            accentColor: projectSidebarHandleAccentColor,
            surfaceStyle: projectSidebarHandleSurfaceStyle,
            translucentBackgroundEnabled: enableTranslucentWindow,
            isActive: projectSidebarResizeHandleIsActive,
            isDragging: projectSidebarResizeStartWidth != nil,
            isHovered: $isProjectSidebarResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Project Sidebar",
            accessibilityHint: "Drag left or right to adjust project sidebar width",
            accessibilityAdjust: { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                let adjusted = min(
                    max(CGFloat(projectSidebarWidth) + delta, minimumProjectSidebarWidth),
                    maximumProjectSidebarWidth
                )
                projectSidebarWidth = Double(adjusted)
            }
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
        return projectSidebarResizeHandleIsActive
            ? Color.accentColor.opacity(0.55)
            : Color.clear
#else
        let isActive = projectSidebarResizeHandleIsActive
        return isActive ? Color.accentColor.opacity(0.70) : projectSidebarHandleDividerColor
#endif
    }

    var projectSidebarResizeHandleAccentWidth: CGFloat {
#if os(macOS)
        projectSidebarResizeHandleIsActive ? 2 : 0
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
        // The resize handle keeps a transparent hit target, but must not add
        // a painted one-pixel strip beside the rounded project card.
        return AnyShapeStyle(Color.clear)
#else
        if enableTranslucentWindow {
            return editorSurfaceBackgroundStyle
        }
        return useIOSUnifiedSolidSurfaces
            ? AnyShapeStyle(iOSNonTranslucentSurfaceColor)
            : AnyShapeStyle(Color.clear)
#endif
    }

    func utilitySidebarHeader(integratedIntoProjectCard: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: utilitySidebarMode.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(utilitySidebarMode.headerTitle)
                        .font(.headline.weight(.semibold))
                    Text(utilitySidebarMode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            Picker("Sidebar Content", selection: Binding(
                get: { utilitySidebarMode },
                set: { utilitySidebarModeRaw = $0.rawValue }
            )) {
                ForEach(UtilitySidebarMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .tint(.accentColor)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, integratedIntoProjectCard ? 2 : 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar Content")
        .accessibilityHint("Choose Project or AI Assistant")
    }

    var utilitySidebarHeaderTopInset: CGFloat {
#if os(macOS)
        8
#else
        0
#endif
    }

    var projectStructureSidebarBody: some View {
        VStack(spacing: 0) {
            if utilitySidebarMode == .assistant {
                utilitySidebarHeader()
                    .padding(.top, utilitySidebarHeaderTopInset)
                aiChatSidebarBody
                    .padding(.top, 8)
            } else {
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
                    gitViewModel: gitViewModel,
                    embeddedHeader: AnyView(utilitySidebarHeader(integratedIntoProjectCard: true))
                )
            }
        }
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
    private(set) static var activeOwnerID: String?
    private static var generation: UInt = 0

    static func set(ownerID: String) {
        generation &+= 1
        activeOwnerID = ownerID
        NSCursor.resizeLeftRight.set()
    }

    static func reset(ownerID: String) {
        guard activeOwnerID == ownerID else { return }
        generation &+= 1
        activeOwnerID = nil
        NSCursor.arrow.set()
    }

}

struct MacSidebarResizeDivider<ResizeGesture: Gesture>: View where ResizeGesture.Value == DragGesture.Value {
    let visibleWidth: CGFloat
    let hitTargetWidth: CGFloat
    let cursorOwnerID: String
    let accentWidth: CGFloat
    let accentColor: Color
    let surfaceStyle: AnyShapeStyle
    let translucentBackgroundEnabled: Bool
    let isActive: Bool
    let isDragging: Bool
    @Binding var isHovered: Bool
    let drag: ResizeGesture
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityAdjust: ((AccessibilityAdjustmentDirection) -> Void)?

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
        .background {
            if translucentBackgroundEnabled {
                MacSidebarResizeTranslucentBackdrop()
            } else {
                Rectangle().fill(surfaceStyle)
            }
        }
        .overlay {
            MacSidebarResizeCursorTrackingView(
                isHovered: $isHovered,
                isDragging: isDragging,
                cursorOwnerID: cursorOwnerID
            )
                .frame(width: hitTargetWidth)
                .contentShape(Rectangle())
                .gesture(drag)
        }
        .onDisappear {
            isHovered = false
            MacSidebarResizeCursor.reset(ownerID: cursorOwnerID)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAdjustableAction { direction in
            accessibilityAdjust?(direction)
        }
    }
}

private struct MacSidebarResizeTranslucentBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        view.autoresizingMask = [.width, .height]
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .underWindowBackground
        nsView.blendingMode = .withinWindow
        nsView.state = .active
    }
}

private struct MacSidebarResizeCursorTrackingView: NSViewRepresentable {
    @Binding var isHovered: Bool
    let isDragging: Bool
    let cursorOwnerID: String

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = { hovering in
            isHovered = hovering
        }
        view.isDragging = isDragging
        view.cursorOwnerID = cursorOwnerID
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = { hovering in
            isHovered = hovering
        }
        nsView.isDragging = isDragging
        nsView.cursorOwnerID = cursorOwnerID
        if isDragging || isHovered {
            MacSidebarResizeCursor.set(ownerID: cursorOwnerID)
        }
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        var isDragging: Bool = false
        var cursorOwnerID: String = "resize-handle"
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .activeInActiveApp,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
            MacSidebarResizeCursor.set(ownerID: cursorOwnerID)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
            guard !isDragging else { return }

            MacSidebarResizeCursor.reset(ownerID: cursorOwnerID)
        }
    }
}
#endif

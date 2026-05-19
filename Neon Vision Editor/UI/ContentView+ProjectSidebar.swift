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
            }

        return ZStack {
            Rectangle()
                .fill(projectSidebarHandleSurfaceStyle)
            Rectangle()
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 1)
                .frame(maxWidth: .infinity, alignment: projectNavigatorPlacement == .leading ? .leading : .trailing)
        }
        .frame(width: projectSidebarResizeHandleWidth)
        .contentShape(Rectangle())
        .gesture(drag)
#if os(macOS)
        .onHover { hovering in
            guard hovering != isProjectSidebarResizeHandleHovered else { return }
            isProjectSidebarResizeHandleHovered = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isProjectSidebarResizeHandleHovered {
                isProjectSidebarResizeHandleHovered = false
                NSCursor.pop()
            }
        }
#endif
        .accessibilityElement()
        .accessibilityLabel("Resize Project Sidebar")
        .accessibilityHint("Drag left or right to adjust project sidebar width")
    }

    var projectSidebarHandleSurfaceStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            return editorSurfaceBackgroundStyle
        }
#if os(iOS)
        return useIOSUnifiedSolidSurfaces
            ? AnyShapeStyle(iOSNonTranslucentSurfaceColor)
            : AnyShapeStyle(Color.clear)
#else
        return AnyShapeStyle(Color.clear)
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
            onRefreshTree: { refreshProjectBrowserState() },
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
            compareDiffPresentation: sidebarCompareDiffPresentation,
            onCloseCompareDiff: { sidebarCompareDiffPresentation = nil },
            revealURL: projectTreeRevealURL,
            gitFileStatusMap: gitViewModel.fileStatusMap,
            gitViewModel: gitViewModel
        )
    }
}

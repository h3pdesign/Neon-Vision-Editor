import Foundation

extension ContentView {
    struct TabChromeObservationSnapshot: Equatable {
        let structureRevision: Int
        let metadataRevision: Int
    }

    struct ProjectNavigationObservationSnapshot: Equatable {
        let rootURL: URL?
        let indexReady: Bool
    }

    struct EditorObservationSnapshot: Equatable {
        let contentRevision: Int
    }

    struct PreviewObservationSnapshot: Equatable {
        let projectEnabled: Bool
        let contentFilter: String
    }

    struct WindowSessionObservationSnapshot: Equatable {
        let persistenceRevision: Int
    }

    struct CommandRoutingObservationSnapshot: Equatable {
        let windowNumber: Int?
    }

    var tabChromeObservationSnapshot: TabChromeObservationSnapshot {
        TabChromeObservationSnapshot(
            structureRevision: viewModel.tabsObservationToken,
            metadataRevision: viewModel.tabMetadataObservationToken
        )
    }

    var projectNavigationObservationSnapshot: ProjectNavigationObservationSnapshot {
        ProjectNavigationObservationSnapshot(
            rootURL: projectRootFolderURL,
            indexReady: projectFileIndexHasCompleted
        )
    }

    var editorObservationSnapshot: EditorObservationSnapshot {
        EditorObservationSnapshot(contentRevision: viewModel.tabContentObservationToken)
    }

    var previewObservationSnapshot: PreviewObservationSnapshot {
        PreviewObservationSnapshot(
            projectEnabled: markdownProjectPreviewEnabled,
            contentFilter: markdownProjectPreviewContentFilterRaw
        )
    }

    var windowSessionObservationSnapshot: WindowSessionObservationSnapshot {
        WindowSessionObservationSnapshot(persistenceRevision: viewModel.tabPersistenceObservationToken)
    }

    var commandRoutingObservationSnapshot: CommandRoutingObservationSnapshot {
#if os(macOS)
        let windowNumber = hostWindowNumber
#else
        let windowNumber: Int? = nil
#endif
        return CommandRoutingObservationSnapshot(windowNumber: windowNumber)
    }

    enum SearchScope: String, CaseIterable, Identifiable {
        case currentFile = "currentFile"
        case openTabs = "openTabs"
        case project = "project"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .currentFile: return "Current File"
            case .openTabs: return "Open Tabs"
            case .project: return "Project"
            }
        }
    }

    enum StartupBehavior {
        case standard
        case forceBlankDocument
        case safeMode
    }

    enum ProjectNavigatorPlacement: String, CaseIterable, Identifiable {
        case leading
        case trailing

        var id: String { rawValue }
    }
}

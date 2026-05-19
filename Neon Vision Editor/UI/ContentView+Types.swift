import Foundation

extension ContentView {
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

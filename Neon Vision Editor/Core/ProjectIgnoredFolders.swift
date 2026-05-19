import Foundation

enum ProjectIgnoredFolders {
    nonisolated static let defaultsKey = "SettingsProjectSidebarIgnoredFolderNames"
    nonisolated static let defaultNames = [".git", ".build", "node_modules", "DerivedData"]
    nonisolated static let knownNames = defaultNames + [".swiftpm", ".derivedData", "build", "dist"]

    nonisolated static var defaultRawValue: String {
        defaultNames.joined(separator: ",")
    }

    nonisolated static func names(from rawValue: String) -> Set<String> {
        Set(
            rawValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    nonisolated static func rawValue(from names: Set<String>) -> String {
        names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ",")
    }
}

struct RecentProjectFoldersStore {
    struct Item: Identifiable, Equatable {
        let url: URL

        var id: String { url.standardizedFileURL.path }
        var title: String { url.lastPathComponent }
        var subtitle: String { url.standardizedFileURL.path }
    }

    private static let pathsKey = "RecentProjectFolderPathsV1"
    private static let maximumItemCount = 10

    static func items(limit: Int = maximumItemCount) -> [Item] {
        sanitizedPaths(from: UserDefaults.standard.stringArray(forKey: pathsKey) ?? [])
            .prefix(limit)
            .map { Item(url: URL(fileURLWithPath: $0)) }
    }

    static func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        var paths = sanitizedPaths(from: UserDefaults.standard.stringArray(forKey: pathsKey) ?? [])
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(maximumItemCount)), forKey: pathsKey)
    }

    private static func sanitizedPaths(from rawPaths: [String]) -> [String] {
        var seen: Set<String> = []
        return rawPaths.compactMap { rawPath in
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            guard !seen.contains(path) else { return nil }
            seen.insert(path)
            return path
        }
    }
}

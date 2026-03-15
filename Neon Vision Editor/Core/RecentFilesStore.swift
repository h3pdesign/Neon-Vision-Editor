import Foundation

struct RecentFilesStore {
    struct Item: Identifiable, Equatable {
        let url: URL
        let isPinned: Bool

        var id: String { url.standardizedFileURL.path }
        var title: String { url.lastPathComponent }
        var subtitle: String { url.standardizedFileURL.path }
    }

    private static let recentPathsKey = "RecentFilesPathsV1"
    private static let pinnedPathsKey = "PinnedRecentFilesPathsV1"
    private static let maximumItemCount = 30

    static func items(limit: Int = maximumItemCount) -> [Item] {
        let defaults = UserDefaults.standard
        let recentPaths = sanitizedPaths(from: defaults.stringArray(forKey: recentPathsKey) ?? [])
        let pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        let pinnedSet = Set(pinnedPaths)

        let orderedPaths = pinnedPaths + recentPaths.filter { !pinnedSet.contains($0) }
        let urls = orderedPaths.prefix(limit).map { URL(fileURLWithPath: $0) }
        return urls.map { Item(url: $0, isPinned: pinnedSet.contains($0.standardizedFileURL.path)) }
    }

    static func remember(_ url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        let defaults = UserDefaults.standard
        var recentPaths = sanitizedPaths(from: defaults.stringArray(forKey: recentPathsKey) ?? [])
        recentPaths.removeAll { $0 == standardizedPath }
        recentPaths.insert(standardizedPath, at: 0)

        let pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        let pinnedSet = Set(pinnedPaths)
        let retainedUnpinned = recentPaths.filter { !pinnedSet.contains($0) }
        let availableUnpinnedSlots = max(0, maximumItemCount - pinnedPaths.count)
        let trimmedRecent = Array(retainedUnpinned.prefix(availableUnpinnedSlots))

        defaults.set(trimmedRecent, forKey: recentPathsKey)
        defaults.set(pinnedPaths, forKey: pinnedPathsKey)
        postDidChange()
    }

    static func togglePinned(_ url: URL) {
        let standardizedPath = url.standardizedFileURL.path
        let defaults = UserDefaults.standard
        var pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        var recentPaths = sanitizedPaths(from: defaults.stringArray(forKey: recentPathsKey) ?? [])

        if let existingIndex = pinnedPaths.firstIndex(of: standardizedPath) {
            pinnedPaths.remove(at: existingIndex)
            recentPaths.removeAll { $0 == standardizedPath }
            recentPaths.insert(standardizedPath, at: 0)
        } else {
            pinnedPaths.removeAll { $0 == standardizedPath }
            pinnedPaths.insert(standardizedPath, at: 0)
            pinnedPaths = Array(pinnedPaths.prefix(maximumItemCount))
            recentPaths.removeAll { $0 == standardizedPath }
        }

        let pinnedSet = Set(pinnedPaths)
        let availableUnpinnedSlots = max(0, maximumItemCount - pinnedPaths.count)
        recentPaths = Array(recentPaths.filter { !pinnedSet.contains($0) }.prefix(availableUnpinnedSlots))

        defaults.set(recentPaths, forKey: recentPathsKey)
        defaults.set(pinnedPaths, forKey: pinnedPathsKey)
        postDidChange()
    }

    static func clearUnpinned() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: recentPathsKey)
        postDidChange()
    }

    private static func sanitizedPaths(from rawPaths: [String]) -> [String] {
        var seen: Set<String> = []
        return rawPaths.compactMap { rawPath in
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            guard !path.isEmpty else { return nil }
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            guard !seen.contains(path) else { return nil }
            seen.insert(path)
            return path
        }
    }

    private static func postDidChange() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .recentFilesDidChange, object: nil)
        }
    }
}

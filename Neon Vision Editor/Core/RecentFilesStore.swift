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
    private static let bookmarkMapKey = "RecentFilesBookmarksV1"
    private static let maximumItemCount = 30

    static func items(
        limit: Int = maximumItemCount,
        defaults: UserDefaults = .standard
    ) -> [Item] {
        let recentPaths = sanitizedPaths(from: defaults.stringArray(forKey: recentPathsKey) ?? [])
        let pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        let pinnedSet = Set(pinnedPaths)
        let bookmarkMap = loadBookmarkMap(from: defaults)

        let orderedPaths = pinnedPaths + recentPaths.filter { !pinnedSet.contains($0) }
        let urls = orderedPaths.prefix(limit).map { resolveURL(forPath: $0, bookmarkMap: bookmarkMap) }
        return urls.map { Item(url: $0, isPinned: pinnedSet.contains($0.standardizedFileURL.path)) }
    }

    static func remember(_ url: URL, defaults: UserDefaults = .standard) {
        let standardizedPath = url.standardizedFileURL.path
        var recentPaths = sanitizedPaths(from: defaults.stringArray(forKey: recentPathsKey) ?? [])
        recentPaths.removeAll { $0 == standardizedPath }
        recentPaths.insert(standardizedPath, at: 0)

        let pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        let pinnedSet = Set(pinnedPaths)
        let retainedUnpinned = recentPaths.filter { !pinnedSet.contains($0) }
        let availableUnpinnedSlots = max(0, maximumItemCount - pinnedPaths.count)
        let trimmedRecent = Array(retainedUnpinned.prefix(availableUnpinnedSlots))

        var bookmarkMap = loadBookmarkMap(from: defaults)
        if bookmarkMap[standardizedPath] == nil,
           let bookmark = makeSecurityScopedBookmark(for: url) {
            bookmarkMap[standardizedPath] = bookmark
        }
        pruneBookmarks(&bookmarkMap, keeping: Set(trimmedRecent).union(pinnedPaths))
        if persist(
            recentPaths: trimmedRecent,
            pinnedPaths: pinnedPaths,
            bookmarkMap: bookmarkMap,
            to: defaults
        ) {
            postDidChange()
        }
    }

    static func togglePinned(_ url: URL, defaults: UserDefaults = .standard) {
        let standardizedPath = url.standardizedFileURL.path
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

        var bookmarkMap = loadBookmarkMap(from: defaults)
        pruneBookmarks(&bookmarkMap, keeping: Set(recentPaths).union(pinnedPaths))
        if persist(
            recentPaths: recentPaths,
            pinnedPaths: pinnedPaths,
            bookmarkMap: bookmarkMap,
            to: defaults
        ) {
            postDidChange()
        }
    }

    static func clearUnpinned(defaults: UserDefaults = .standard) {
        let pinnedPaths = sanitizedPaths(from: defaults.stringArray(forKey: pinnedPathsKey) ?? [])
        var bookmarkMap = loadBookmarkMap(from: defaults)
        pruneBookmarks(&bookmarkMap, keeping: Set(pinnedPaths))
        if persist(
            recentPaths: nil,
            pinnedPaths: pinnedPaths,
            bookmarkMap: bookmarkMap,
            to: defaults
        ) {
            postDidChange()
        }
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

    private static func loadBookmarkMap(from defaults: UserDefaults) -> [String: Data] {
        guard let raw = defaults.dictionary(forKey: bookmarkMapKey) else { return [:] }
        var output: [String: Data] = [:]
        output.reserveCapacity(raw.count)
        for (path, value) in raw {
            guard let data = value as? Data else { continue }
            output[path] = data
        }
        return output
    }

    private static func persist(
        recentPaths: [String]?,
        pinnedPaths: [String],
        bookmarkMap: [String: Data],
        to defaults: UserDefaults
    ) -> Bool {
        var didChange = false

        if let recentPaths, defaults.stringArray(forKey: recentPathsKey) != recentPaths {
            defaults.set(recentPaths, forKey: recentPathsKey)
            didChange = true
        } else if recentPaths == nil, defaults.object(forKey: recentPathsKey) != nil {
            defaults.removeObject(forKey: recentPathsKey)
            didChange = true
        }
        if defaults.stringArray(forKey: pinnedPathsKey) != pinnedPaths {
            defaults.set(pinnedPaths, forKey: pinnedPathsKey)
            didChange = true
        }
        if !bookmarkMapMatchesStoredValue(bookmarkMap, in: defaults) {
            defaults.set(bookmarkMap, forKey: bookmarkMapKey)
            didChange = true
        }

        return didChange
    }

    private static func bookmarkMapMatchesStoredValue(_ map: [String: Data], in defaults: UserDefaults) -> Bool {
        guard let raw = defaults.dictionary(forKey: bookmarkMapKey) else {
            return map.isEmpty
        }
        guard raw.count == map.count else { return false }
        return raw.allSatisfy { path, value in
            map[path] == value as? Data
        }
    }

    private static func pruneBookmarks(_ map: inout [String: Data], keeping paths: Set<String>) {
        map = map.filter { paths.contains($0.key) }
    }

    private static func resolveURL(forPath path: String, bookmarkMap: [String: Data]) -> URL {
        guard let bookmarkData = bookmarkMap[path] else {
            return URL(fileURLWithPath: path)
        }
        var isStale = false
        guard
            let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        else {
            return URL(fileURLWithPath: path)
        }
        return resolved.standardizedFileURL
    }

    private static func makeSecurityScopedBookmark(for url: URL) -> Data? {
        let didAccess: Bool
        #if os(macOS)
        didAccess = url.startAccessingSecurityScopedResource()
        #else
        didAccess = false
        #endif
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try? url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }
}

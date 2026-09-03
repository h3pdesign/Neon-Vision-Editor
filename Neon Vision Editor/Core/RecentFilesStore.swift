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
        let recentPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: recentPathsKey, defaults: defaults) as? [String]) ?? [])
        let pinnedPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: pinnedPathsKey, defaults: defaults) as? [String]) ?? [])
        let pinnedSet = Set(pinnedPaths)
        let bookmarkMap = loadBookmarkMap(from: defaults)

        let orderedPaths = pinnedPaths + recentPaths.filter { !pinnedSet.contains($0) }
        let urls = orderedPaths.prefix(limit).map { resolveURL(forPath: $0, bookmarkMap: bookmarkMap) }
        return urls.map { Item(url: $0, isPinned: pinnedSet.contains($0.standardizedFileURL.path)) }
    }

    static func remember(_ url: URL, defaults: UserDefaults = .standard) {
        let standardizedPath = url.standardizedFileURL.path
        var recentPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: recentPathsKey, defaults: defaults) as? [String]) ?? [])
        recentPaths.removeAll { $0 == standardizedPath }
        recentPaths.insert(standardizedPath, at: 0)

        let pinnedPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: pinnedPathsKey, defaults: defaults) as? [String]) ?? [])
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
        var pinnedPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: pinnedPathsKey, defaults: defaults) as? [String]) ?? [])
        var recentPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: recentPathsKey, defaults: defaults) as? [String]) ?? [])

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
        let pinnedPaths = sanitizedPaths(from: (EditorPreferenceWriter.shared.object(forKey: pinnedPathsKey, defaults: defaults) as? [String]) ?? [])
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
        guard let raw = (EditorPreferenceWriter.shared.object(forKey: bookmarkMapKey, defaults: defaults) as? [String: Any]) else { return [:] }
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

        if let recentPaths, (EditorPreferenceWriter.shared.object(forKey: recentPathsKey, defaults: defaults) as? [String]) != recentPaths {
            EditorPreferenceWriter.shared.set(.paths(recentPaths), forKey: recentPathsKey, defaults: defaults)
            didChange = true
        } else if recentPaths == nil, EditorPreferenceWriter.shared.object(forKey: recentPathsKey, defaults: defaults) != nil {
            EditorPreferenceWriter.shared.set(.removed, forKey: recentPathsKey, defaults: defaults)
            didChange = true
        }
        if (EditorPreferenceWriter.shared.object(forKey: pinnedPathsKey, defaults: defaults) as? [String]) != pinnedPaths {
            EditorPreferenceWriter.shared.set(.paths(pinnedPaths), forKey: pinnedPathsKey, defaults: defaults)
            didChange = true
        }
        if !bookmarkMapMatchesStoredValue(bookmarkMap, in: defaults) {
            EditorPreferenceWriter.shared.set(.bookmarks(bookmarkMap), forKey: bookmarkMapKey, defaults: defaults)
            didChange = true
        }

        return didChange
    }

    private static func bookmarkMapMatchesStoredValue(_ map: [String: Data], in defaults: UserDefaults) -> Bool {
        guard let raw = (EditorPreferenceWriter.shared.object(forKey: bookmarkMapKey, defaults: defaults) as? [String: Any]) else {
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

/// Keep preference reads immediately consistent while serializing disk writes and
/// synchronous UserDefaults observers away from editor activation and drawing.
@MainActor
final class EditorPreferenceWriter {
    static let shared = EditorPreferenceWriter()

    nonisolated enum Value: Sendable {
        case paths([String])
        case bookmarks([String: Data])
        case data(Data)
        case removed

        var object: Any? {
            switch self {
            case .paths(let value): return value
            case .bookmarks(let value): return value
            case .data(let value): return value
            case .removed: return nil
            }
        }
    }

    private nonisolated struct Key: Hashable, Sendable {
        let defaultsID: ObjectIdentifier
        let name: String
    }

    // Foundation supports concurrent UserDefaults access. The wrapper transfers
    // that reference to the serial writer without transferring UI-owned state.
    private nonisolated struct Store: @unchecked Sendable {
        let defaults: UserDefaults
    }

    private nonisolated struct Write: Sendable {
        let revision: UUID
        let value: Value
        let store: Store
    }

    private nonisolated final class PendingWrites: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Key: Write] = [:]

        func replace(_ value: Write, for key: Key) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let needsWorker = values[key] == nil
            values[key] = value
            return needsWorker
        }

        func take(_ key: Key) -> Write? {
            lock.lock()
            defer { lock.unlock() }
            return values.removeValue(forKey: key)
        }
    }

    private let queue = DispatchQueue(label: "editor.preferences.persistence", qos: .utility)
    private let pendingWrites = PendingWrites()
    private var pending: [Key: (revision: UUID, value: Value, defaults: UserDefaults)] = [:]

    func object(forKey name: String, defaults: UserDefaults = .standard) -> Any? {
        let key = Key(defaultsID: ObjectIdentifier(defaults), name: name)
        if let value = pending[key]?.value { return value.object }
        return defaults.object(forKey: name)
    }

    func set(_ value: Value, forKey name: String, defaults: UserDefaults = .standard) {
        let key = Key(defaultsID: ObjectIdentifier(defaults), name: name)
        let revision = UUID()
        pending[key] = (revision, value, defaults)
        let write = Write(revision: revision, value: value, store: Store(defaults: defaults))
        // Repeated opens can supersede the same preference while an observer is
        // still handling its prior write. Persist the latest queued value rather
        // than accumulating obsolete snapshots that delay shutdown.
        guard pendingWrites.replace(write, for: key) else { return }
        let pendingWrites = pendingWrites
        queue.async {
            guard let write = pendingWrites.take(key) else { return }
            if let object = write.value.object {
                write.store.defaults.set(object, forKey: name)
            } else {
                write.store.defaults.removeObject(forKey: name)
            }
            Task { @MainActor [self] in
                if pending[key]?.revision == write.revision { pending.removeValue(forKey: key) }
            }
        }
    }

    func flushBeforeTermination() {
        // The worker never waits for the main actor; only app termination waits
        // for persistence, so an immediate quit cannot lose the latest recents.
        queue.sync {}
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}

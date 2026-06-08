import Foundation

struct SharedImportStore {
    struct Item: Identifiable, Equatable {
        let url: URL
        let importedAt: Date

        var id: String { url.standardizedFileURL.path }
        var title: String { url.lastPathComponent }
        var subtitle: String { url.standardizedFileURL.path }
    }

    private struct StoredItem: Codable, Equatable {
        var path: String
        var importedAt: Date
    }

    private static let itemsKey = "SharedImportHistoryV1"
    private static let maximumItemCount = 20
    private static let maximumImportAge: TimeInterval = 30 * 24 * 60 * 60

    static func items(limit: Int = maximumItemCount) -> [Item] {
        pruneExpiredImports()
        return loadItems()
            .prefix(limit)
            .compactMap { stored in
                let url = URL(fileURLWithPath: stored.path).standardizedFileURL
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return Item(url: url, importedAt: stored.importedAt)
            }
    }

    static func remember(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let now = Date()
        var stored = loadItems()
        let newPaths = urls.map { $0.standardizedFileURL.path }
        stored.removeAll { newPaths.contains($0.path) }
        stored.insert(contentsOf: newPaths.map { StoredItem(path: $0, importedAt: now) }, at: 0)
        save(Array(stored.prefix(maximumItemCount)))
        pruneExpiredImports()
        postDidChange()
    }

    static func clearHistory() {
        UserDefaults.standard.removeObject(forKey: itemsKey)
        postDidChange()
    }

    static func pruneExpiredImports(now: Date = Date()) {
        guard let importDirectory = ShareImportHandoff.sharedImportDirectory() else { return }
        let cutoff = now.addingTimeInterval(-maximumImportAge)
        let stored = loadItems().filter { item in
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            return item.importedAt >= cutoff && FileManager.default.fileExists(atPath: url.path)
        }
        save(Array(stored.prefix(maximumItemCount)))

        let trackedPaths = Set(stored.map(\.path))
        let files = (try? FileManager.default.contentsOfDirectory(
            at: importDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in files {
            guard !trackedPaths.contains(file.standardizedFileURL.path) else { continue }
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private static func loadItems() -> [StoredItem] {
        guard let data = UserDefaults.standard.data(forKey: itemsKey),
              let decoded = try? JSONDecoder().decode([StoredItem].self, from: data) else {
            return []
        }
        var seen: Set<String> = []
        return decoded.compactMap { item in
            let path = URL(fileURLWithPath: item.path).standardizedFileURL.path
            guard !path.isEmpty, !seen.contains(path) else { return nil }
            seen.insert(path)
            return StoredItem(path: path, importedAt: item.importedAt)
        }
    }

    private static func save(_ items: [StoredItem]) {
        let data = try? JSONEncoder().encode(items)
        UserDefaults.standard.set(data, forKey: itemsKey)
    }

    private static func postDidChange() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .sharedImportsDidChange, object: nil)
        }
    }
}

import Foundation

struct ProjectFileIndex {
    struct Entry: Sendable, Hashable {
        let url: URL
        let standardizedPath: String
        let relativePath: String
        let displayName: String
        let contentModificationDate: Date?
        let fileSize: Int64?
    }

    struct Snapshot: Sendable {
        let entries: [Entry]

        nonisolated static let empty = Snapshot(entries: [])

        var fileURLs: [URL] {
            entries.map(\.url)
        }
    }

    nonisolated static func buildSnapshot(
        at root: URL,
        supportedOnly: Bool,
        isSupportedFile: @escaping @Sendable (URL) -> Bool
    ) async -> Snapshot {
        await Task.detached(priority: .utility) {
            buildSnapshotSync(
                at: root,
                supportedOnly: supportedOnly,
                isSupportedFile: isSupportedFile
            )
        }.value
    }

    nonisolated static func refreshSnapshot(
        _ previous: Snapshot,
        at root: URL,
        supportedOnly: Bool,
        isSupportedFile: @escaping @Sendable (URL) -> Bool
    ) async -> Snapshot {
        await Task.detached(priority: .utility) {
            refreshSnapshotSync(
                previous,
                at: root,
                supportedOnly: supportedOnly,
                isSupportedFile: isSupportedFile
            )
        }.value
    }

    private nonisolated static func buildSnapshotSync(
        at root: URL,
        supportedOnly: Bool,
        isSupportedFile: @escaping @Sendable (URL) -> Bool
    ) -> Snapshot {
        let previous = Snapshot.empty
        return refreshSnapshotSync(
            previous,
            at: root,
            supportedOnly: supportedOnly,
            isSupportedFile: isSupportedFile
        )
    }

    private nonisolated static func refreshSnapshotSync(
        _ previous: Snapshot,
        at root: URL,
        supportedOnly: Bool,
        isSupportedFile: @escaping @Sendable (URL) -> Bool
    ) -> Snapshot {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
            .contentModificationDateKey,
            .fileSizeKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsHiddenFiles,
            .skipsPackageDescendants
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: options
        ) else {
            return .empty
        }

        let previousByPath = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.standardizedPath, $0) })
        var refreshedEntries: [Entry] = []
        refreshedEntries.reserveCapacity(max(previous.entries.count, 512))

        while let fileURL = enumerator.nextObject() as? URL {
            if Task.isCancelled {
                return previous
            }
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys) else {
                continue
            }
            if values.isHidden == true {
                if values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }
            if supportedOnly && !isSupportedFile(fileURL) {
                continue
            }

            let standardizedURL = fileURL.standardizedFileURL
            let standardizedPath = standardizedURL.path
            let modificationDate = values.contentModificationDate
            let fileSize = values.fileSize.map(Int64.init)

            if let previousEntry = previousByPath[standardizedPath],
               previousEntry.contentModificationDate == modificationDate,
               previousEntry.fileSize == fileSize {
                refreshedEntries.append(previousEntry)
                continue
            }

            let relativePath = relativePathForFile(standardizedURL, root: root)
            refreshedEntries.append(
                Entry(
                    url: standardizedURL,
                    standardizedPath: standardizedPath,
                    relativePath: relativePath,
                    displayName: values.name ?? standardizedURL.lastPathComponent,
                    contentModificationDate: modificationDate,
                    fileSize: fileSize
                )
            )
        }

        refreshedEntries.sort {
            $0.standardizedPath.localizedCaseInsensitiveCompare($1.standardizedPath) == .orderedAscending
        }
        return Snapshot(entries: refreshedEntries)
    }

    private nonisolated static func relativePathForFile(_ fileURL: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let trimmed = String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? fileURL.lastPathComponent : trimmed
    }
}

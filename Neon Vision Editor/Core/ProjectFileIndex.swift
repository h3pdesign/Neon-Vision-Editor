import Foundation

struct ProjectFileIndex {
    static func buildFileURLs(
        at root: URL,
        supportedOnly: Bool,
        isSupportedFile: @escaping @Sendable (URL) -> Bool
    ) async -> [URL] {
        await Task.detached(priority: .utility) {
            let resourceKeys: [URLResourceKey] = [
                .isRegularFileKey,
                .isDirectoryKey,
                .isHiddenKey,
                .nameKey
            ]
            let options: FileManager.DirectoryEnumerationOptions = [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ]
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: options
            ) else {
                return []
            }

            var results: [URL] = []
            results.reserveCapacity(512)

            while let fileURL = enumerator.nextObject() as? URL {
                if Task.isCancelled {
                    return []
                }
                guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)) else {
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
                results.append(fileURL)
            }

            return results.sorted {
                $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
        }.value
    }
}

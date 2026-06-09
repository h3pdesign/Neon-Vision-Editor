import Foundation

enum ShareImportHandoff {
    static let appGroupIdentifier = "group.h3p.Neon-Vision-Editor"
    static let urlScheme = "neonvisioneditor"
    static let importHost = "share-import"
    static let importDirectoryName = "SharedImports"
    private static let pendingManifestFilename = "PendingSharedImports.json"

    static func isShareImportURL(_ url: URL) -> Bool {
        url.scheme == urlScheme && url.host == importHost
    }

    static func sharedImportDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = container.appendingPathComponent(importDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func importedFileURLs(from url: URL) -> [URL] {
        guard isShareImportURL(url) else { return [] }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let importDirectory = sharedImportDirectory() else {
            return []
        }
        let filePaths = components.queryItems?.filter { $0.name == "file" }.compactMap(\.value) ?? []
        return sanitizedImportedFileURLs(from: filePaths, importDirectory: importDirectory)
    }

    static func consumePendingImportedFileURLs() -> [URL] {
        guard let importDirectory = sharedImportDirectory() else { return [] }
        let manifestURL = importDirectory.appendingPathComponent(pendingManifestFilename, isDirectory: false)
        guard let data = try? Data(contentsOf: manifestURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let filePaths = payload["filePaths"] as? [String] else {
            return []
        }
        try? FileManager.default.removeItem(at: manifestURL)
        return sanitizedImportedFileURLs(from: filePaths, importDirectory: importDirectory)
    }

    private static func sanitizedImportedFileURLs(from filePaths: [String], importDirectory: URL) -> [URL] {
        let allowedRoot = importDirectory.standardizedFileURL.path
        var seen: Set<String> = []
        return filePaths.compactMap { filePath in
            let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
            let path = fileURL.path
            guard path.hasPrefix(allowedRoot + "/"), FileManager.default.fileExists(atPath: path), !seen.contains(path) else {
                return nil
            }
            seen.insert(path)
            return fileURL
        }
    }
}

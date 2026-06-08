import Foundation

enum ShareImportHandoff {
    static let appGroupIdentifier = "group.h3p.Neon-Vision-Editor"
    static let urlScheme = "neonvisioneditor"
    static let importHost = "share-import"
    static let importDirectoryName = "SharedImports"

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
        let allowedRoot = importDirectory.standardizedFileURL.path
        return filePaths.compactMap { filePath in
            let fileURL = URL(fileURLWithPath: filePath).standardizedFileURL
            guard fileURL.path.hasPrefix(allowedRoot + "/") else { return nil }
            return fileURL
        }
    }
}

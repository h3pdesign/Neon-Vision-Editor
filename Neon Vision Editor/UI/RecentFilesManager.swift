import Foundation
import Combine

/// Manages a list of recently opened files, persisted to UserDefaults.
@MainActor
final class RecentFilesManager: ObservableObject {
    static let shared = RecentFilesManager()
    
    private let userDefaultsKey = "RecentFiles"
    private let maxRecentFiles = 10
    
    @Published private(set) var recentFiles: [URL] = []
    
    private init() {
        loadRecentFiles()
    }
    
    /// Add a file URL to the recent files list.
    func addRecentFile(_ url: URL) {
        // Start security-scoped resource access for sandboxed apps
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Remove if already present to avoid duplicates
        recentFiles.removeAll { $0 == url }
        
        // Insert at the beginning
        recentFiles.insert(url, at: 0)
        
        // Keep only the most recent files
        if recentFiles.count > maxRecentFiles {
            recentFiles = Array(recentFiles.prefix(maxRecentFiles))
        }
        
        saveRecentFiles()
    }
    
    /// Remove a file URL from the recent files list.
    func removeRecentFile(_ url: URL) {
        recentFiles.removeAll { $0 == url }
        saveRecentFiles()
    }
    
    /// Clear all recent files.
    func clearRecentFiles() {
        recentFiles.removeAll()
        saveRecentFiles()
    }
    
    /// Check if a file still exists and is accessible.
    func fileExists(_ url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// Remove files that no longer exist from the recent files list.
    func cleanupDeletedFiles() {
        let existingFiles = recentFiles.filter { fileExists($0) }
        if existingFiles.count != recentFiles.count {
            recentFiles = existingFiles
            saveRecentFiles()
        }
    }
    
    /// Generate a display name for a file URL, including parent folders to disambiguate duplicates.
    /// - Parameter url: The file URL
    /// - Parameter depth: Number of parent folders to include (default: 2)
    /// - Returns: A display name like "Folder1/Folder2/Item.swift"
    func displayName(for url: URL, depth: Int = 2) -> String {
        let pathComponents = url.pathComponents
        let fileName = url.lastPathComponent
        
        // If the path is too short, just return the filename
        guard pathComponents.count > 1 else {
            return fileName
        }
        
        // Get the parent folders (up to 'depth' levels)
        let startIndex = max(0, pathComponents.count - depth - 1)
        let endIndex = pathComponents.count - 1
        
        let relevantComponents = Array(pathComponents[startIndex..<endIndex])
        
        // Filter out empty components and the root "/"
        let filteredComponents = relevantComponents.filter { !$0.isEmpty && $0 != "/" }
        
        if filteredComponents.isEmpty {
            return fileName
        }
        
        return (filteredComponents + [fileName]).joined(separator: "/")
    }
    
    /// Generate unique display names for all recent files, showing more path context if needed to disambiguate.
    /// - Returns: Dictionary mapping URLs to their display names
    func uniqueDisplayNames() -> [URL: String] {
        var result: [URL: String] = [:]
        var nameGroups: [String: [URL]] = [:]
        
        // Group URLs by filename
        for url in recentFiles {
            let fileName = url.lastPathComponent
            nameGroups[fileName, default: []].append(url)
        }
        
        // For each group, determine the appropriate display name
        for (fileName, urls) in nameGroups {
            if urls.count == 1 {
                // No conflict, just use the filename
                result[urls[0]] = fileName
            } else {
                // Conflict! Show parent folders to disambiguate
                for url in urls {
                    result[url] = displayName(for: url, depth: 2)
                }
                
                // If there are still duplicates after showing 2 levels, try 3 levels
                let displayNames = urls.map { result[$0] ?? fileName }
                if Set(displayNames).count < urls.count {
                    for url in urls {
                        result[url] = displayName(for: url, depth: 3)
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Persistence
    
    private func loadRecentFiles() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let bookmarks = try? JSONDecoder().decode([Data].self, from: data) else {
            recentFiles = []
            return
        }
        
        var urls: [URL] = []
        for bookmark in bookmarks {
            var isStale = false
            #if os(macOS)
            let resolveOptions: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let resolveOptions: URL.BookmarkResolutionOptions = []
            #endif
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: resolveOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                urls.append(url)
            }
        }
        
        recentFiles = urls
    }
    
    private func saveRecentFiles() {
        var bookmarks: [Data] = []
        
        for url in recentFiles {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            #if os(macOS)
            let createOptions: URL.BookmarkCreationOptions = .withSecurityScope
            #else
            let createOptions: URL.BookmarkCreationOptions = []
            #endif
            if let bookmark = try? url.bookmarkData(
                options: createOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                bookmarks.append(bookmark)
            }
        }
        
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}

import Foundation

nonisolated enum EditorAgentMode: String, CaseIterable, Identifiable, Sendable {
    case explore
    case edit
    case verify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .explore: "Explore"
        case .edit: "Edit"
        case .verify: "Verify"
        }
    }
}

nonisolated enum EditorAgentVerificationAction: String, CaseIterable, Sendable {
    case none
    case syntax
    case build
    case tests
    case runSelectedFile

    var title: String {
        switch self {
        case .none: "No verification"
        case .syntax: "Check Syntax"
        case .build: "Build Project"
        case .tests: "Run Tests"
        case .runSelectedFile: "Run Selected File"
        }
    }
}

nonisolated struct EditorAgentEditProposal: Identifiable, Equatable, Sendable {
    let id = UUID()
    let tabID: UUID
    let range: NSRange
    let source: String
    let replacement: String
    let summary: String

    func matches(tabID: UUID, range: NSRange, currentSource: String) -> Bool {
        self.tabID == tabID && self.range == range && source == currentSource
    }
}

nonisolated enum EditorAgentProcessingLocation: String, Sendable {
    case onDevice
    case privateCloudCompute

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .privateCloudCompute: "Private Cloud Compute"
        }
    }
}

nonisolated struct EditorAgentEditTarget: Equatable, Sendable {
    let tabID: UUID
    let range: NSRange
    let source: String
}

nonisolated public struct EditorAgentRunResult: Sendable {
    let responseMarkdown: String
    let editProposal: EditorAgentEditProposal?
    let verificationAction: EditorAgentVerificationAction
    let verificationReason: String
    let processingLocation: EditorAgentProcessingLocation
    let activity: [EditorAgentActivity]
}

nonisolated enum EditorAgentActivityKind: String, Sendable {
    case read
    case search
    case model
    case verification
}

nonisolated enum EditorAgentActivityStatus: String, Sendable {
    case started
    case succeeded
    case failed
    case blocked
}

nonisolated struct EditorAgentActivity: Identifiable, Equatable, Sendable {
    let id = UUID()
    let date = Date()
    let kind: EditorAgentActivityKind
    let title: String
    let status: EditorAgentActivityStatus
}

nonisolated struct EditorAgentSearchResult: Equatable, Sendable {
    let relativePath: String
    let snippet: String
}

nonisolated enum EditorAgentWorkspaceError: LocalizedError {
    case invalidPath
    case fileNotAllowed
    case unreadableFile
    case invalidQuery

    var errorDescription: String? {
        switch self {
        case .invalidPath: "The requested path is outside the captured project."
        case .fileNotAllowed: "The requested file was not included in the captured project snapshot."
        case .unreadableFile: "The requested file could not be read as text."
        case .invalidQuery: "Enter at least two visible characters to search the project."
        }
    }
}

actor EditorAgentWorkspace {
    private static let maximumReadBytes = 256 * 1024
    private static let maximumSearchFiles = 300
    private static let maximumSnippetCharacters = 600

    let rootURL: URL
    private let resolvedRootURL: URL
    private let allowedURLsByRelativePath: [String: URL]
    private var activity: [EditorAgentActivity] = []

    init(rootURL: URL, allowedFileURLs: [URL]) {
        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var allowlistedURLs: [String: URL] = [:]
        for candidate in allowedFileURLs {
            let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard Self.isContained(resolved, by: resolvedRoot) else { continue }
            allowlistedURLs[Self.relativePath(for: resolved, root: resolvedRoot)] = resolved
        }
        self.rootURL = rootURL.standardizedFileURL
        self.resolvedRootURL = resolvedRoot
        self.allowedURLsByRelativePath = allowlistedURLs
    }

    func readFile(relativePath: String, maximumCharacters: Int = 8_000) throws -> String {
        activity.append(.init(kind: .read, title: "Read \(relativePath)", status: .started))
        do {
            let url = try allowedURL(for: relativePath)
            let text = try Self.boundedText(at: url, maximumBytes: Self.maximumReadBytes)
            let bounded = String(text.prefix(max(1, min(maximumCharacters, 20_000))))
            activity.append(.init(kind: .read, title: "Read \(relativePath)", status: .succeeded))
            return bounded
        } catch {
            activity.append(.init(kind: .read, title: "Read \(relativePath)", status: .blocked))
            throw error
        }
    }

    func searchProject(query: String, maximumResults: Int = 8) throws -> [EditorAgentSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else { throw EditorAgentWorkspaceError.invalidQuery }
        activity.append(.init(kind: .search, title: "Search captured project", status: .started))

        let limit = max(1, min(maximumResults, 12))
        var results: [EditorAgentSearchResult] = []
        for relativePath in allowedURLsByRelativePath.keys.sorted().prefix(Self.maximumSearchFiles) {
            guard results.count < limit,
                  let url = allowedURLsByRelativePath[relativePath],
                  let text = try? Self.boundedText(at: url, maximumBytes: Self.maximumReadBytes),
                  let match = text.range(of: trimmedQuery, options: [.caseInsensitive, .diacriticInsensitive]) else {
                continue
            }
            let matchOffset = text.distance(from: text.startIndex, to: match.lowerBound)
            let lowerOffset = max(0, matchOffset - Self.maximumSnippetCharacters / 3)
            let upperOffset = min(text.count, lowerOffset + Self.maximumSnippetCharacters)
            let lower = text.index(text.startIndex, offsetBy: lowerOffset)
            let upper = text.index(text.startIndex, offsetBy: upperOffset)
            results.append(.init(relativePath: relativePath, snippet: String(text[lower..<upper])))
        }

        activity.append(.init(
            kind: .search,
            title: "Found \(results.count) project result\(results.count == 1 ? "" : "s")",
            status: .succeeded
        ))
        return results
    }

    func activitySnapshot() -> [EditorAgentActivity] {
        activity
    }

    func record(_ item: EditorAgentActivity) {
        activity.append(item)
    }

    private func allowedURL(for relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw EditorAgentWorkspaceError.invalidPath
        }
        let candidate = resolvedRootURL
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard Self.isContained(candidate, by: resolvedRootURL) else {
            throw EditorAgentWorkspaceError.invalidPath
        }
        let normalizedRelativePath = Self.relativePath(for: candidate, root: resolvedRootURL)
        guard let allowedURL = allowedURLsByRelativePath[normalizedRelativePath] else {
            throw EditorAgentWorkspaceError.fileNotAllowed
        }
        return allowedURL
    }

    private nonisolated static func boundedText(at url: URL, maximumBytes: Int) throws -> String {
        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess { url.stopAccessingSecurityScopedResource() }
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumBytes) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else {
            throw EditorAgentWorkspaceError.unreadableFile
        }
        return text
    }

    private nonisolated static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let rootPath = root.path
        let candidatePath = candidate.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private nonisolated static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.path
        let path = url.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }
}

nonisolated struct EditorAgentVerificationPlan: Equatable, Sendable {
    let action: EditorAgentVerificationAction
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL

    var displayCommand: String {
        ([executableURL.path] + arguments).map(Self.shellDisplayValue).joined(separator: " ")
    }

    private static func shellDisplayValue(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace || "'\"\\$;&|<>".contains($0) }) else { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

nonisolated enum EditorAgentVerificationResolver {
    static func plan(
        for action: EditorAgentVerificationAction,
        rootURL: URL,
        selectedFileURL: URL?
    ) -> EditorAgentVerificationPlan? {
        let root = rootURL.standardizedFileURL
        switch action {
        case .none:
            return nil
        case .syntax:
            guard let selectedFileURL,
                  selectedFileURL.pathExtension.lowercased() == "swift",
                  isContained(selectedFileURL, by: root) else { return nil }
            return .init(
                action: action,
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["swiftc", "-parse", selectedFileURL.path],
                workingDirectoryURL: root
            )
        case .runSelectedFile:
            guard let selectedFileURL, isContained(selectedFileURL, by: root) else { return nil }
            switch selectedFileURL.pathExtension.lowercased() {
            case "swift":
                return .init(
                    action: action,
                    executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                    arguments: ["swift", selectedFileURL.path],
                    workingDirectoryURL: root
                )
            case "py":
                return .init(
                    action: action,
                    executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
                    arguments: [selectedFileURL.path],
                    workingDirectoryURL: root
                )
            default:
                return nil
            }
        case .build, .tests:
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("Package.swift").path) {
                return .init(
                    action: action,
                    executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
                    arguments: [action == .build ? "build" : "test"],
                    workingDirectoryURL: root
                )
            }
            guard let project = firstProject(in: root) else { return nil }
            let scheme = project.deletingPathExtension().lastPathComponent
            return .init(
                action: action,
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: [
                    "-project", project.path,
                    "-scheme", scheme,
                    "-destination", "platform=macOS",
                    action == .build ? "build" : "test"
                ],
                workingDirectoryURL: root
            )
        }
    }

    private static func firstProject(in root: URL) -> URL? {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents?
            .filter { $0.pathExtension.lowercased() == "xcodeproj" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first
    }

    private static func isContained(_ candidate: URL, by root: URL) -> Bool {
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolvedCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        return resolvedCandidate.path == resolvedRoot.path || resolvedCandidate.path.hasPrefix(resolvedRoot.path + "/")
    }
}

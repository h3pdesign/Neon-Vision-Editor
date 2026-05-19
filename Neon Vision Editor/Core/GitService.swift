import Foundation

// MARK: - Git Models

enum GitFileStatus: String, Sendable, Equatable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case conflicted = "U"
    case untracked = "?"
    case clean = " "

    var displayIcon: String {
        switch self {
        case .modified: return "pencil.circle"
        case .added: return "plus.circle"
        case .deleted: return "minus.circle"
        case .renamed: return "arrow.right.circle"
        case .conflicted: return "exclamationmark.circle"
        case .untracked: return "questionmark.circle"
        case .copied: return "doc.on.doc"
        case .clean: return "checkmark.circle"
        }
    }
}

struct GitFileEntry: Sendable, Equatable, Identifiable {
    let path: String
    let status: GitFileStatus
    let staged: Bool
    var id: String { path + (staged ? "-staged" : "-unstaged") }
}

struct GitCommit: Sendable, Identifiable {
    let hash: String
    let author: String
    let email: String
    let date: Date
    let message: String
    var id: String { hash }
}

struct GitHistoryEntry: Sendable, Equatable, Identifiable {
    let hash: String
    let graph: String
    let author: String
    let date: Date
    let decorations: [String]
    let message: String
    let parentHashes: [String]
    let parentCount: Int
    let insertions: Int
    let deletions: Int

    nonisolated var id: String { hash }
    nonisolated var shortHash: String { String(hash.prefix(7)) }
    nonisolated var isMerge: Bool { parentCount > 1 }
    nonisolated var hasChangeStat: Bool { insertions > 0 || deletions > 0 }
}

struct GitCommitFileChange: Sendable, Equatable, Identifiable {
    let status: String
    let path: String
    let previousPath: String?

    nonisolated var id: String { "\(status)|\(previousPath ?? "")|\(path)" }
}

struct GitCommitDetail: Sendable, Equatable, Identifiable {
    let hash: String
    let parentHashes: [String]
    let author: String
    let email: String
    let date: Date
    let decorations: [String]
    let subject: String
    let body: String
    let shortStat: String
    let files: [GitCommitFileChange]

    nonisolated var id: String { hash }
    nonisolated var shortHash: String { String(hash.prefix(7)) }
    nonisolated var isMerge: Bool { parentHashes.count > 1 }
}

struct GitCommitDiff: Sendable, Equatable {
    let title: String
    let leftTitle: String
    let rightTitle: String
    let leftContent: String
    let rightContent: String
}

// MARK: - Git Service

actor GitService {
    private let repoURL: URL
    private let commitDiffFileLimit = 40
    private let commitDiffBlobByteLimit = 400_000

    static func initializeRepository(at projectURL: URL) async throws {
#if os(macOS)
        try await Task.detached(priority: .userInitiated) {
            _ = try runGitCommand(["init"], in: projectURL)
        }.value
#else
        throw GitError.commandFailed("Git setup is unavailable on this platform.")
#endif
    }

    init?(projectURL: URL) {
#if os(macOS)
        let gitPath = projectURL.appendingPathComponent(".git").path
        guard FileManager.default.fileExists(atPath: gitPath) else { return nil }
        repoURL = projectURL
#else
        return nil
#endif
    }

    var currentBranch: String {
        get throws {
            try readCurrentBranch()
        }
    }

    private func readCurrentBranch() throws -> String {
        do {
            let branch = try runGit(["symbolic-ref", "--quiet", "--short", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !branch.isEmpty {
                return branch
            }
        } catch {
            let hash = try runGit(["rev-parse", "--short", "HEAD"])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !hash.isEmpty {
                return hash
            }
        }
        return "detached"
    }

    // MARK: - Status and History

    func status() -> [GitFileEntry] {
        let raw = (try? runGit(["status", "--porcelain=v1", "-z", "--untracked-files=all"])) ?? ""
        guard !raw.isEmpty else { return [] }

        let records = raw.split(separator: "\0", omittingEmptySubsequences: true)
        var entries: [GitFileEntry] = []
        var index = 0

        while index < records.count {
            let record = String(records[index])
            index += 1
            guard record.count >= 3 else { continue }

            let xChar = record[record.startIndex]
            let yChar = record[record.index(after: record.startIndex)]
            let pathStart = record.index(record.startIndex, offsetBy: 3)
            var path = String(record[pathStart...])

            // Porcelain v1 -z emits a second path record for renames/copies.
            if xChar == "R" || xChar == "C" {
                guard index < records.count else { continue }
                path = String(records[index])
                index += 1
            }

            let stagedStatus = mapStatusChar(xChar)
            if stagedStatus != .clean {
                entries.append(GitFileEntry(path: path, status: stagedStatus, staged: true))
            }

            let unstagedStatus = mapStatusChar(yChar)
            if unstagedStatus != .clean {
                entries.append(GitFileEntry(path: path, status: unstagedStatus, staged: false))
            }
        }

        return entries
    }

    func shortStat() -> (ahead: Int, behind: Int) {
        guard let output = try? runGit(["rev-list", "--left-right", "--count", "@{upstream}...HEAD"]) else {
            return (0, 0)
        }
        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2,
              let behind = Int(parts[0]),
              let ahead = Int(parts[1]) else {
            return (0, 0)
        }
        return (ahead, behind)
    }

    func recentCommits(count: Int = 5) -> [GitCommit] {
        let format = "%H%x1f%an%x1f%ae%x1f%at%x1f%s"
        guard let output = try? runGit(["log", "-n", String(max(1, count)), "--pretty=format:\(format)"]) else {
            return []
        }
        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count >= 5,
                      let timestampSec = Double(fields[3]) else { return nil }
                let hash = String(fields[0])
                return GitCommit(
                    hash: String(hash.prefix(7)),
                    author: String(fields[1]),
                    email: String(fields[2]),
                    date: Date(timeIntervalSince1970: timestampSec),
                    message: String(fields[4])
                )
            }
    }

    func historyGraph(count: Int = 80) -> [GitHistoryEntry] {
        let format = "%x1e%H%x1f%P%x1f%an%x1f%at%x1f%D%x1f%s"
        guard let output = try? runGit([
            "log",
            "--graph",
            "--date=unix",
            "--decorate=short",
            "--all",
            "--max-count=\(max(1, count))",
            "--pretty=format:\(format)"
        ]) else {
            return []
        }

        return output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitHistoryEntry? in
                guard let separatorIndex = line.firstIndex(of: "\u{1e}") else { return nil }
                let graph = String(line[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
                let payloadStart = line.index(after: separatorIndex)
                let fields = line[payloadStart...].split(separator: "\u{1f}", omittingEmptySubsequences: false)
                guard fields.count >= 6,
                      let timestampSec = Double(fields[3]) else { return nil }

                let parentCount = fields[1]
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .count
                let parentHashes = fields[1]
                    .split(separator: " ", omittingEmptySubsequences: true)
                    .map(String.init)
                let decorations = fields[4]
                    .split(separator: ",", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

                let hash = String(fields[0])
                let changeStat = commitChangeStat(hash: hash)

                return GitHistoryEntry(
                    hash: hash,
                    graph: graph.isEmpty ? "*" : graph,
                    author: String(fields[2]),
                    date: Date(timeIntervalSince1970: timestampSec),
                    decorations: decorations,
                    message: String(fields[5]),
                    parentHashes: parentHashes,
                    parentCount: parentCount,
                    insertions: changeStat.insertions,
                    deletions: changeStat.deletions
                )
            }
    }

    // MARK: - Commit Details and Diffs

    func commitDetail(hash: String) throws -> GitCommitDetail {
        let metadataFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1f%B"
        let metadata = try runGit(["show", "--no-ext-diff", "-s", "--date=unix", "--format=\(metadataFormat)", hash])
        let fields = metadata.split(separator: "\u{1f}", omittingEmptySubsequences: false)
        guard fields.count >= 8,
              let timestampSec = Double(fields[4]) else {
            throw GitError.commandFailed("Cannot parse commit details.")
        }

        let parentHashes = fields[1]
            .split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let decorations = fields[5]
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let fileOutput = (try? runGit(["show", "--no-ext-diff", "--find-renames", "--format=", "--name-status", hash])) ?? ""
        let statOutput = (try? runGit(["show", "--no-ext-diff", "--shortstat", "--format=", hash])) ?? ""

        return GitCommitDetail(
            hash: String(fields[0]),
            parentHashes: parentHashes,
            author: String(fields[2]),
            email: String(fields[3]),
            date: Date(timeIntervalSince1970: timestampSec),
            decorations: decorations,
            subject: String(fields[6]),
            body: String(fields[7]).trimmingCharacters(in: .whitespacesAndNewlines),
            shortStat: statOutput.trimmingCharacters(in: .whitespacesAndNewlines),
            files: parseNameStatus(fileOutput)
        )
    }

    func commitDiff(hash: String) throws -> GitCommitDiff {
        let detail = try commitDetail(hash: hash)
        let parentHash = detail.parentHashes.first
        var leftContent = ""
        var rightContent = ""

        for file in detail.files.prefix(commitDiffFileLimit) {
            let leftPath = file.previousPath ?? file.path
            let rightPath = file.path
            let header = commitDiffHeader(for: file)

            leftContent += header
            rightContent += header

            if !file.status.hasPrefix("A"), let parentHash {
                leftContent += blobContent(revision: parentHash, path: leftPath)
            }

            if !file.status.hasPrefix("D") {
                rightContent += blobContent(revision: detail.hash, path: rightPath)
            }
        }

        if detail.files.count > commitDiffFileLimit {
            let remaining = detail.files.count - commitDiffFileLimit
            let message = "\n\n--- \(remaining) additional files not shown ---\n"
            leftContent += message
            rightContent += message
        }

        let titleSuffix = detail.isMerge ? " against first parent" : ""
        return GitCommitDiff(
            title: "Commit \(detail.shortHash)\(titleSuffix)",
            leftTitle: parentHash.map { "Parent \(String($0.prefix(7)))" } ?? "Empty Tree",
            rightTitle: "Commit \(detail.shortHash)",
            leftContent: leftContent,
            rightContent: rightContent
        )
    }

    private func parseNameStatus(_ output: String) -> [GitCommitFileChange] {
        output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line -> GitCommitFileChange? in
                let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard parts.count >= 2 else { return nil }
                if (parts[0].hasPrefix("R") || parts[0].hasPrefix("C")), parts.count >= 3 {
                    return GitCommitFileChange(status: parts[0], path: parts[2], previousPath: parts[1])
                }
                return GitCommitFileChange(status: parts[0], path: parts[1], previousPath: nil)
            }
    }

    private func commitChangeStat(hash: String) -> (insertions: Int, deletions: Int) {
        let output = (try? runGit(["show", "--no-ext-diff", "--shortstat", "--format=", hash])) ?? ""
        return parseShortStat(output)
    }

    private func parseShortStat(_ output: String) -> (insertions: Int, deletions: Int) {
        let tokens = output
            .replacingOccurrences(of: ",", with: "")
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        var insertions = 0
        var deletions = 0

        for index in tokens.indices {
            guard index > tokens.startIndex, let value = Int(tokens[tokens.index(before: index)]) else {
                continue
            }
            if tokens[index].hasPrefix("insertion") {
                insertions = value
            } else if tokens[index].hasPrefix("deletion") {
                deletions = value
            }
        }

        return (insertions, deletions)
    }

    private func commitDiffHeader(for file: GitCommitFileChange) -> String {
        if let previousPath = file.previousPath {
            return "\n\n--- \(file.status) \(previousPath) -> \(file.path) ---\n"
        }
        return "\n\n--- \(file.status) \(file.path) ---\n"
    }

    private func blobContent(revision: String, path: String) -> String {
        let spec = "\(revision):\(path)"
        if let size = try? blobSize(spec: spec), size > commitDiffBlobByteLimit {
            return "[Skipped large file: \(size) bytes]\n"
        }
        do {
            return try runGit(["show", "--no-ext-diff", spec])
        } catch {
            return "[Unable to load \(path): \(error.localizedDescription)]\n"
        }
    }

    private func blobSize(spec: String) throws -> Int {
        let output = try runGit(["cat-file", "-s", spec])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output) ?? 0
    }

    private func mapStatusChar(_ c: Character) -> GitFileStatus {
        switch c {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "U": return .conflicted
        case "?": return .untracked
        default: return .clean
        }
    }

    // MARK: - Git Mutations and Process Execution

    func stage(_ path: String) throws {
        _ = try runGit(["add", path])
    }

    func unstage(_ path: String) throws {
        _ = try runGit(["reset", "HEAD", "--", path])
    }

    func discard(_ path: String) throws {
        _ = try runGit(["checkout", "--", path])
    }

    func commit(message: String) throws {
        _ = try runGit(["commit", "-m", message])
    }

    func fetch() async throws {
        _ = try runGit(["fetch", "--quiet"])
    }

    func pull() async throws {
        _ = try runGit(["pull", "--ff-only", "--quiet"])
    }

    func push() async throws {
        _ = try runGit(["push", "--quiet"])
    }

    func diff(file: String, staged: Bool) throws -> String {
        if staged {
            return try runGit(["diff", "--cached", file])
        }
        return try runGit(["diff", file])
    }

    private func runGit(_ args: [String]) throws -> String {
#if os(macOS)
        return try Self.runGitCommand(args, in: repoURL)
#else
        throw GitError.commandFailed("Git integration is unavailable on this platform.")
#endif
    }

#if os(macOS)
    private static func runGitCommand(_ args: [String], in directoryURL: URL) throws -> String {
        let process = Process()
        process.executableURL = try gitExecutableURL()
        process.arguments = args
        process.currentDirectoryURL = directoryURL
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let outputCollector = GitProcessOutputCollector()
        let errorCollector = GitProcessOutputCollector()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            outputCollector.append(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            errorCollector.append(handle.availableData)
        }
        defer {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitError.commandFailed("Cannot run git: \(error.localizedDescription). Install Xcode Command Line Tools.")
        }

        let errorData = errorCollector.data()
        if process.terminationStatus != 0 {
            let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed(error)
        }

        return String(data: outputCollector.data(), encoding: .utf8) ?? ""
    }

    private static func gitExecutableURL() throws -> URL {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/git",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/git",
            "/opt/homebrew/bin/git",
            "/usr/local/bin/git"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw GitError.commandFailed("Cannot find a sandbox-compatible Git executable. Install Xcode Command Line Tools.")
    }
#endif
}

// MARK: - Process Output and Errors

private final class GitProcessOutputCollector: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var storage = Data()

    nonisolated func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    nonisolated func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

enum GitError: LocalizedError {
    case commandFailed(String)
    case notARepository
    case gitNotInstalled

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .notARepository: return "Not a git repository."
        case .gitNotInstalled: return "Git is not installed."
        }
    }
}

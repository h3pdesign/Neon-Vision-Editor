import Foundation

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

actor GitService {
    private let repoURL: URL

    init?(projectURL: URL) {
#if os(macOS)
        let gitPath = projectURL.appendingPathComponent(".git").path
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: gitPath, isDirectory: &isDir), isDir.boolValue else { return nil }
        repoURL = projectURL
#else
        return nil
#endif
    }

    private var gitDir: URL { repoURL.appendingPathComponent(".git") }

    var currentBranch: String {
        get throws {
            try readBranchFromFile()
        }
    }

    private func readBranchFromFile() throws -> String {
        let headPath = gitDir.appendingPathComponent("HEAD").path
        guard let content = try? String(contentsOfFile: headPath, encoding: .utf8) else {
            throw GitError.commandFailed("Cannot read .git/HEAD")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst(16))
        }
        if trimmed.contains(" ") == false, trimmed.count == 40 {
            return String(trimmed.prefix(7))
        }
        return "detached"
    }

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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = repoURL
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw GitError.commandFailed("Cannot run git: \(error.localizedDescription). Install Xcode Command Line Tools.")
        }

        let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed(error)
        }

        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: outputData, encoding: .utf8) ?? ""
#else
        throw GitError.commandFailed("Git integration is unavailable on this platform.")
#endif
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

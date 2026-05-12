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
    private let git: String

    init?(projectURL: URL) {
#if os(macOS)
        let gitDir = projectURL.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir.path) else { return nil }
        repoURL = projectURL
        let which = ProcessInfo.processInfo.environment["GIT_PATH"] ?? "/usr/bin/git"
        guard FileManager.default.isExecutableFile(atPath: which) else { return nil }
        git = which
#else
        return nil
#endif
    }

    private func run(_ args: [String]) throws -> String {
#if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = args
        process.currentDirectoryURL = repoURL

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw GitError.commandFailed(error)
        }

        return String(data: outputData, encoding: .utf8) ?? ""
#else
        throw GitError.commandFailed("Git is only available on macOS.")
#endif
    }

    var currentBranch: String {
        get throws {
            let output = try run(["rev-parse", "--abbrev-ref", "HEAD"])
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func status() throws -> [GitFileEntry] {
        let output = try run(["status", "--porcelain"])
        var entries: [GitFileEntry] = []
        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            guard line.count >= 3 else { continue }
            let stagedChar = line[line.startIndex]
            let workingChar = line[line.index(after: line.startIndex)]
            let path = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)

            let stagedStatus = GitFileStatus(rawValue: String(stagedChar)) ?? .clean
            let workingStatus = GitFileStatus(rawValue: String(workingChar)) ?? .clean

            if stagedStatus != .clean {
                entries.append(GitFileEntry(path: path, status: stagedStatus, staged: true))
            }
            if workingStatus != .clean {
                entries.append(GitFileEntry(path: path, status: workingStatus, staged: false))
            }
            if stagedStatus == .clean && workingStatus == .clean && stagedChar == "?" {
                entries.append(GitFileEntry(path: path, status: .untracked, staged: false))
            }
        }
        return entries
    }

    func stage(_ path: String) throws {
        _ = try run(["add", path])
    }

    func unstage(_ path: String) throws {
        _ = try run(["reset", "HEAD", "--", path])
    }

    func discard(_ path: String) throws {
        _ = try run(["checkout", "--", path])
    }

    func commit(message: String) throws {
        _ = try run(["commit", "-m", message])
    }

    func fetch() async throws {
        _ = try run(["fetch", "--quiet"])
    }

    func pull() async throws {
        _ = try run(["pull", "--ff-only", "--quiet"])
    }

    func push() async throws {
        _ = try run(["push", "--quiet"])
    }

    func recentCommits(count: Int = 5) throws -> [GitCommit] {
        let output = try run(["log", "--oneline", "--max-count=\(count)", "--format=%H||%an||%ae||%ct||%s"])
        return output.components(separatedBy: "\n").filter { !$0.isEmpty }.compactMap { line in
            let parts = line.components(separatedBy: "||")
            guard parts.count >= 5 else { return nil }
            let timestamp = TimeInterval(parts[3]) ?? 0
            return GitCommit(
                hash: String(parts[0].prefix(7)),
                author: parts[1],
                email: parts[2],
                date: Date(timeIntervalSince1970: timestamp),
                message: parts[4]
            )
        }
    }

    func diff(file: String, staged: Bool) throws -> String {
        if staged {
            return try run(["diff", "--cached", file])
        }
        return try run(["diff", file])
    }

    func shortStat() throws -> (ahead: Int, behind: Int) {
        let output = try? run(["rev-list", "--left-right", "--count", "HEAD...@{u}"])
        guard let output, !output.isEmpty else { return (0, 0) }
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        guard parts.count >= 2 else { return (0, 0) }
        return (Int(parts[0]) ?? 0, Int(parts[1]) ?? 0)
    }
}

enum GitError: LocalizedError {
    case commandFailed(String)
    case notARepository
    case gitNotInstalled

    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return "Git: \(msg)"
        case .notARepository: return "Not a git repository."
        case .gitNotInstalled: return "Git is not installed."
        }
    }
}

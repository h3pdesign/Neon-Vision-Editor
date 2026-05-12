import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class GitViewModel {
    private(set) var gitService: GitService?
    private(set) var entries: [GitFileEntry] = []
    private(set) var branch: String = ""
    private(set) var ahead: Int = 0
    private(set) var behind: Int = 0
    private(set) var commits: [GitCommit] = []
    private(set) var isOperating = false
    private(set) var statusMessage: String?
    private(set) var isRepo: Bool = false
    private(set) var projectURL: URL?

    func fileURL(for path: String) -> URL? {
        projectURL?.appendingPathComponent(path)
    }
    private var scanTask: Task<Void, Never>?

    func setProjectURL(_ url: URL?) {
        projectURL = url
        guard let url else {
            gitService = nil
            isRepo = false
            entries = []
            branch = ""
            return
        }
        gitService = GitService(projectURL: url)
        isRepo = gitService != nil
        if gitService != nil {
            refresh()
        }
    }

    func refresh() {
        scanTask?.cancel()
        scanTask = Task {
            guard let git = gitService else { return }
            do {
                let newBranch = try await git.currentBranch
                let newEntries = await git.status()
                let stat = await git.shortStat()
                let newCommits = await git.recentCommits()

                if !Task.isCancelled {
                    branch = newBranch
                    entries = newEntries
                    ahead = stat.ahead
                    behind = stat.behind
                    commits = newCommits
                }
            } catch {
                if !Task.isCancelled {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func stage(_ path: String) {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.stage(path)
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func unstage(_ path: String) {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.unstage(path)
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func discard(_ path: String) {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.discard(path)
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func commit(message: String) {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.commit(message: message)
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func fetch() {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.fetch()
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func pull() {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.pull()
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func push() {
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await gitService?.push()
                refresh()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    var fileStatusMap: [String: GitFileStatus] {
        var map: [String: GitFileStatus] = [:]
        for entry in entries where !entry.staged {
            map[entry.path] = entry.status
        }
        return map
    }
}

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class GitViewModel {
    private(set) var gitService: GitService?
    private(set) var entries: [GitFileEntry] = []
    private(set) var fileStatusMap: [String: GitFileStatus] = [:]
    private(set) var branch: String = ""
    private(set) var ahead: Int = 0
    private(set) var behind: Int = 0
    private(set) var commits: [GitCommit] = []
    private(set) var history: [GitHistoryEntry] = []
    private(set) var selectedCommitDetail: GitCommitDetail?
    private(set) var isLoadingCommitDetail = false
    private(set) var isPreparingCommitDiff = false
    private(set) var isOperating = false
    private(set) var statusMessage: String?
    private(set) var isRepo: Bool = false
    private(set) var projectURL: URL?
    var canInitializeRepository: Bool { projectURL != nil && !isRepo && !isOperating }

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
            fileStatusMap = [:]
            branch = ""
            ahead = 0
            behind = 0
            commits = []
            history = []
            selectedCommitDetail = nil
            isLoadingCommitDetail = false
            isPreparingCommitDiff = false
            statusMessage = nil
            return
        }
        gitService = GitService(projectURL: url)
        isRepo = gitService != nil
        if gitService == nil {
            entries = []
            fileStatusMap = [:]
            branch = ""
            ahead = 0
            behind = 0
            commits = []
            history = []
            selectedCommitDetail = nil
            isLoadingCommitDetail = false
            isPreparingCommitDiff = false
            statusMessage = nil
        }
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
                let newFileStatusMap = Self.makeFileStatusMap(from: newEntries)
                let stat = await git.shortStat()
                let newCommits = await git.recentCommits()
                let newHistory = await git.historyGraph()

                if !Task.isCancelled {
                    branch = newBranch
                    entries = newEntries
                    fileStatusMap = newFileStatusMap
                    ahead = stat.ahead
                    behind = stat.behind
                    commits = newCommits
                    history = newHistory
                    if let selectedCommitDetail,
                       newHistory.contains(where: { $0.hash == selectedCommitDetail.hash }) == false {
                        self.selectedCommitDetail = nil
                    }
                    statusMessage = nil
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

    func selectHistoryEntry(_ entry: GitHistoryEntry) {
        Task {
            guard let git = gitService else { return }
            isLoadingCommitDetail = true
            isPreparingCommitDiff = true
            defer { isLoadingCommitDetail = false }
            defer { isPreparingCommitDiff = false }
            do {
                selectedCommitDetail = try await git.commitDetail(hash: entry.hash)
                statusMessage = nil
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func prepareCommitDiff(for entry: GitHistoryEntry) async -> GitCommitDiff? {
        guard let git = gitService else { return nil }
        isLoadingCommitDetail = true
        isPreparingCommitDiff = true
        defer { isLoadingCommitDetail = false }
        defer { isPreparingCommitDiff = false }
        do {
            let detail = try await git.commitDetail(hash: entry.hash)
            selectedCommitDetail = detail
            let diff = try await git.commitDiff(hash: entry.hash)
            statusMessage = nil
            return diff
        } catch {
            statusMessage = error.localizedDescription
            return nil
        }
    }

    func initializeRepository() {
        guard let projectURL else { return }
        Task {
            isOperating = true
            defer { isOperating = false }
            do {
                try await GitService.initializeRepository(at: projectURL)
                setProjectURL(projectURL)
                statusMessage = nil
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private nonisolated static func makeFileStatusMap(from entries: [GitFileEntry]) -> [String: GitFileStatus] {
        var map: [String: GitFileStatus] = [:]
        map.reserveCapacity(entries.count)
        for entry in entries where !entry.staged {
            map[entry.path] = entry.status
        }
        return map
    }
}

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
    private var detailTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var projectGeneration = 0

    func setProjectURL(_ url: URL?) {
        projectGeneration += 1
        scanTask?.cancel()
        detailTask?.cancel()
        operationTask?.cancel()
        scanTask = nil
        detailTask = nil
        operationTask = nil
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
        let generation = projectGeneration
        guard let git = gitService else { return }
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let newBranch = try await git.currentBranch
                let newEntries = await git.status()
                let newFileStatusMap = Self.makeFileStatusMap(from: newEntries)
                let stat = await git.shortStat()
                let newCommits = await git.recentCommits()
                let newHistory = await git.historyGraph()

                if !Task.isCancelled, generation == self.projectGeneration, self.gitService === git {
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
                if !Task.isCancelled, generation == self.projectGeneration, self.gitService === git {
                    statusMessage = error.localizedDescription
                }
            }
        }
    }

    func stage(_ path: String) {
        performOperation { try await $0.stage(path) }
    }

    func unstage(_ path: String) {
        performOperation { try await $0.unstage(path) }
    }

    func discard(_ path: String) {
        performOperation { try await $0.discard(path) }
    }

    func commit(message: String) {
        performOperation { try await $0.commit(message: message) }
    }

    func fetch() {
        performOperation { try await $0.fetch() }
    }

    func pull() {
        performOperation { try await $0.pull() }
    }

    func push() {
        performOperation { try await $0.push() }
    }

    func selectHistoryEntry(_ entry: GitHistoryEntry) {
        detailTask?.cancel()
        let generation = projectGeneration
        guard let git = gitService else { return }
        detailTask = Task { [weak self] in
            guard let self else { return }
            isLoadingCommitDetail = true
            isPreparingCommitDiff = true
            defer { isLoadingCommitDetail = false }
            defer { isPreparingCommitDiff = false }
            do {
                let detail = try await git.commitDetail(hash: entry.hash)
                guard !Task.isCancelled, generation == self.projectGeneration, self.gitService === git else { return }
                selectedCommitDetail = detail
                statusMessage = nil
            } catch {
                if !Task.isCancelled, generation == self.projectGeneration, self.gitService === git {
                    statusMessage = error.localizedDescription
                }
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
            let diff = try await git.commitDiff(detail: detail)
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

    private func performOperation(_ operation: @escaping (GitService) async throws -> Void) {
        operationTask?.cancel()
        let generation = projectGeneration
        guard let git = gitService else { return }
        operationTask = Task { [weak self] in
            guard let self else { return }
            isOperating = true
            defer { isOperating = false }
            do {
                try await operation(git)
                guard !Task.isCancelled, generation == self.projectGeneration, self.gitService === git else { return }
                refresh()
            } catch {
                if !Task.isCancelled, generation == self.projectGeneration, self.gitService === git {
                    statusMessage = error.localizedDescription
                }
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

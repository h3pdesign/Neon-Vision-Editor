import SwiftUI

struct GitTabView: View {
    @State var gitViewModel: GitViewModel
    let onShowDiff: ((String, String, String) -> Void)?
    @State private var commitMessage: String = ""
    @Environment(\.colorScheme) private var colorScheme

    init(gitViewModel: GitViewModel, onShowDiff: ((String, String, String) -> Void)? = nil) {
        self.gitViewModel = gitViewModel
        self.onShowDiff = onShowDiff
    }

    private var surfaceBackground: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }

    var body: some View {
        VStack(spacing: 0) {
            if !gitViewModel.isRepo {
                ContentUnavailableView(
                    "No Git Repository",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Open a project folder that contains a .git directory.")
                )
            } else if let errorMsg = gitViewModel.statusMessage {
                ContentUnavailableView(
                    "Git Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMsg)
                )
            } else if gitViewModel.branch.isEmpty {
                ContentUnavailableView(
                    "Loading…",
                    systemImage: "arrow.triangle.branch",
                    description: Text("Reading repository state…")
                )
            } else {
                branchHeader
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                Divider()
                changesList
                Divider()
                commitBar
                    .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground)
    }

    private var branchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(gitViewModel.branch.isEmpty ? "—" : gitViewModel.branch)
                    .font(.title2.weight(.semibold))
                if gitViewModel.ahead > 0 || gitViewModel.behind > 0 {
                    Text("\(gitViewModel.behind) behind  ·  \(gitViewModel.ahead) ahead")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("Up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            HStack(spacing: 8) {
                gitButton("Fetch", icon: "arrow.down.circle") { gitViewModel.fetch() }
                gitButton("Pull", icon: "arrow.triangle.merge") { gitViewModel.pull() }
                gitButton("Push", icon: "arrow.up.circle") { gitViewModel.push() }
            }
        }
    }

    private func gitButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(gitViewModel.isOperating)
    }

    private var changesList: some View {
        let staged = gitViewModel.entries.filter { $0.staged }
        let unstaged = gitViewModel.entries.filter { !$0.staged }

        return Group {
            if gitViewModel.entries.isEmpty {
                ContentUnavailableView(
                    "Working tree is clean",
                    systemImage: "checkmark.circle",
                    description: Text("No changes to show.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !staged.isEmpty {
                        Section("Staged  (\(staged.count))") {
                            ForEach(staged) { entry in
                                fileRow(entry, color: .green)
                            }
                        }
                    }
                    if !unstaged.isEmpty {
                        Section("Changes  (\(unstaged.count))") {
                            ForEach(unstaged) { entry in
                                fileRow(entry, color: .purple)
                            }
                        }
                    }
                    if !gitViewModel.commits.isEmpty {
                        Section("Recent Commits") {
                            ForEach(gitViewModel.commits) { commit in
                                commitRow(commit)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func fileRow(_ entry: GitFileEntry, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.status.displayIcon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 20)
            if entry.status == .modified || entry.status == .added {
                Button {
                    loadAndShowDiff(for: entry)
                } label: {
                    Text(entry.path)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(entry.path)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer()
            if entry.staged {
                Button("Unstage") { gitViewModel.unstage(entry.path) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else if entry.status != .deleted && entry.status != .untracked {
                Button("Stage") { gitViewModel.stage(entry.path) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func commitRow(_ commit: GitCommit) -> some View {
        HStack(spacing: 10) {
            Text(commit.hash)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(commit.message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer()
            Text(commit.author)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(commit.date, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var commitBar: some View {
        HStack(spacing: 12) {
            TextField("Commit message…", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .disabled(gitViewModel.isOperating)
                .onSubmit { submitCommit() }

            Button(gitViewModel.isOperating ? "Working…" : "Commit") {
                submitCommit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || gitViewModel.isOperating)
        }
    }

    private func submitCommit() {
        let msg = commitMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        gitViewModel.commit(message: msg)
        commitMessage = ""
    }

    private func loadAndShowDiff(for entry: GitFileEntry) {
        guard let onShowDiff, let fileURL = gitViewModel.fileURL(for: entry.path) else { return }
        Task {
            let content = await Task.detached { () -> String in
                (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            }.value
            onShowDiff(entry.path, "", content)
        }
    }
}

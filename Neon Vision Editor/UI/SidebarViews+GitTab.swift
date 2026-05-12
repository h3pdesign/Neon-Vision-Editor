import SwiftUI

struct GitTabView: View {
    @State var gitViewModel: GitViewModel
    @State private var commitMessage: String = ""
    @Environment(\.colorScheme) private var colorScheme

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                branchHeader
                changesSection
                commitSection
                recentCommitsSection
            }
        }
        .background(surfaceBackground)
    }

    private var branchHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(gitViewModel.branch.isEmpty ? "—" : gitViewModel.branch)
                .font(.caption.weight(.semibold))
            if gitViewModel.ahead > 0 || gitViewModel.behind > 0 {
                HStack(spacing: 4) {
                    if gitViewModel.behind > 0 {
                        Text("↓\(gitViewModel.behind)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if gitViewModel.ahead > 0 {
                        Text("↑\(gitViewModel.ahead)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                gitActionButton("Fetch") { gitViewModel.fetch() }
                gitActionButton("Pull") { gitViewModel.pull() }
                gitActionButton("Push") { gitViewModel.push() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private func gitActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(gitViewModel.isOperating)
    }

    private var changesSection: some View {
        let staged = gitViewModel.entries.filter { $0.staged }
        let unstaged = gitViewModel.entries.filter { !$0.staged }

        return Group {
            if gitViewModel.entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Working tree is clean")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                if !staged.isEmpty {
                    changeGroup("Staged", entries: staged, color: .green)
                }
                if !unstaged.isEmpty {
                    changeGroup("Changes", entries: unstaged, color: .purple)
                }
            }
        }
    }

    private func changeGroup(_ title: String, entries: [GitFileEntry], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title) (\(entries.count))")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Image(systemName: entry.status.displayIcon)
                        .font(.caption)
                        .foregroundStyle(color)
                        .frame(width: 16)
                    Text(entry.path)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if entry.staged {
                        Button("Unstage") { gitViewModel.unstage(entry.path) }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    } else if entry.status != .deleted {
                        Button("Stage") { gitViewModel.stage(entry.path) }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
        }
    }

    private var commitSection: some View {
        VStack(spacing: 6) {
            TextField("Commit message…", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .frame(maxWidth: .infinity)
                .disabled(gitViewModel.isOperating)
                .onSubmit { submitCommit() }

            Button(gitViewModel.isOperating ? "Working…" : "Commit") {
                submitCommit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || gitViewModel.isOperating)
        }
        .padding(12)
    }

    private func submitCommit() {
        let msg = commitMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        gitViewModel.commit(message: msg)
        commitMessage = ""
    }

    private var recentCommitsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Recent Commits")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if gitViewModel.commits.isEmpty {
                Text("No commits yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            } else {
                ForEach(gitViewModel.commits) { commit in
                    HStack(spacing: 6) {
                        Text(commit.hash)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        Text(commit.message)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(commit.date, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

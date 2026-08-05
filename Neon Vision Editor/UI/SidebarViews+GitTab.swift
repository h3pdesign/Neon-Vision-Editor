import SwiftUI

// MARK: - Git Editor Surface

private enum GitTabSection: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case history = "History"
    case graph = "Graph"

    var id: String { rawValue }
}

private struct GitCommitPreview: Identifiable {
    let id = UUID()
    let message: String
}

struct GitChangesEditorView: View {
    @State var gitViewModel: GitViewModel
    let onClose: (() -> Void)?
    let translucentBackgroundEnabled: Bool
    @State private var commitMessage: String = ""
    @State private var selectedSection: GitTabSection = .changes
    @State private var inlineDiff: DocumentDiffPresentation?
    @State private var selectedHistoryHash: String?
    @State private var pendingCommit: GitCommitPreview?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif

    init(
        gitViewModel: GitViewModel,
        translucentBackgroundEnabled: Bool = false,
        onClose: (() -> Void)? = nil
    ) {
        self.gitViewModel = gitViewModel
        self.translucentBackgroundEnabled = translucentBackgroundEnabled
        self.onClose = onClose
    }

    private var surfaceBackground: AnyShapeStyle {
        if translucentBackgroundEnabled {
#if os(macOS)
            switch macTranslucencyModeRaw {
            case "subtle":
                return AnyShapeStyle(.thickMaterial.opacity(0.82))
            case "vibrant":
                return AnyShapeStyle(.regularMaterial.opacity(0.62))
            default:
                return AnyShapeStyle(.thickMaterial.opacity(0.72))
            }
#else
            return AnyShapeStyle(.ultraThinMaterial)
#endif
        }
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
    }

    private var isCompactWidth: Bool {
#if os(macOS)
        false
#else
        horizontalSizeClass == .compact
#endif
    }

    private var alignedDiffHeaderHeight: CGFloat {
        isCompactWidth ? 128 : 64
    }

    var body: some View {
        VStack(spacing: 0) {
            if !gitViewModel.isRepo {
                gitSetupView
            } else if let errorMsg = gitViewModel.statusMessage {
                ZStack(alignment: .topTrailing) {
                    ContentUnavailableView(
                        "Git Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMsg)
                    )
                    gitCloseButton
                        .padding(16)
                }
            } else if gitViewModel.branch.isEmpty {
                ZStack(alignment: .topTrailing) {
                    ContentUnavailableView(
                        "Loading…",
                        systemImage: "arrow.triangle.branch",
                        description: Text("Reading repository state…")
                    )
                    gitCloseButton
                        .padding(16)
                }
            } else {
                editorHeader
                Divider()
                Group {
                    if isCompactWidth {
                        VStack(spacing: 0) {
                            gitControlsColumn
                            Divider()
                            inlineDiffPane
                        }
                    } else {
                        HStack(spacing: 0) {
                            gitControlsColumn
                            Divider()
                            inlineDiffPane
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground)
        .task {
            selectLatestCommitIfNeeded()
        }
        .onChange(of: gitViewModel.history.first?.id) { _, _ in
            selectLatestCommitIfNeeded()
        }
        .confirmationDialog(
            "Commit staged changes?",
            isPresented: Binding(
                get: { pendingCommit != nil },
                set: { isPresented in
                    if !isPresented { pendingCommit = nil }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Commit") {
                guard let preview = pendingCommit else { return }
                gitViewModel.commit(message: preview.message)
                commitMessage = ""
                pendingCommit = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let preview = pendingCommit {
                let stagedCount = gitViewModel.entries.filter(\.staged).count
                Text("Create a commit on \(gitViewModel.branch) containing \(stagedCount) staged file\(stagedCount == 1 ? "" : "s"). Message: \(preview.message)")
            } else {
                Text("No pending commit.")
            }
        }
    }

    private var gitControlsColumn: some View {
        VStack(spacing: 0) {
                        branchHeader
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .frame(height: alignedDiffHeaderHeight, alignment: .top)
                        Divider()
                        sectionPicker
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        Divider()
                        selectedContent
                        if selectedSection == .changes {
                            Divider()
                            commitBar
                                .padding(12)
                        }
                    }
        .frame(minWidth: isCompactWidth ? 0 : 360, idealWidth: isCompactWidth ? nil : 430, maxWidth: isCompactWidth ? .infinity : 520, maxHeight: isCompactWidth ? 300 : .infinity)
        .layoutPriority(isCompactWidth ? 0 : 1)
    }

    @ViewBuilder
    private var inlineDiffPane: some View {
        if let inlineDiff {
            InlineDiffView(
                presentation: inlineDiff,
                translucentBackgroundEnabled: translucentBackgroundEnabled
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        } else if gitViewModel.isPreparingCommitDiff {
            ProgressView("Preparing diff…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Select a Change",
                systemImage: "rectangle.split.2x1",
                description: Text("The latest commit diff will appear here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Working Copy Changes")
                    .font(.headline.weight(.semibold))
                Text(gitViewModel.entries.isEmpty ? "Clean working tree" : "\(gitViewModel.entries.count) changed file\(gitViewModel.entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                gitViewModel.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .disabled(gitViewModel.isOperating)
            .help("Refresh Git status")
            if let onClose {
                Button(action: onClose) {
                    Label("Close Git Changes", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Close Git Changes")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Working Copy Changes")
    }

    @ViewBuilder
    private var gitCloseButton: some View {
        if let onClose {
            Button(action: onClose) {
                Label("Close Git Changes", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close Git Changes")
            .accessibilityHint("Returns to the editor")
        }
    }

    private var gitSetupView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "No Git Repository",
                systemImage: "arrow.triangle.branch",
                description: Text(gitViewModel.projectURL == nil
                                  ? "Open a project folder to use Git."
                                  : "This project folder does not contain a Git repository.")
            )
            if let message = gitViewModel.statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Button {
                gitViewModel.initializeRepository()
            } label: {
                Label(
                    gitViewModel.isOperating ? "Setting Up Git…" : "Initialize Git Repository",
                    systemImage: "plus.circle"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(!gitViewModel.canInitializeRepository)
            .accessibilityHint("Creates a local Git repository in the opened project folder.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(alignment: .topTrailing) {
            gitCloseButton
                .padding(16)
        }
    }

    private var sectionPicker: some View {
        Picker("Git Section", selection: $selectedSection) {
            ForEach(GitTabSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Git section")
    }

    // MARK: - Git Content Sections

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .changes:
            changesList
        case .history:
            historyList
        case .graph:
            graphCanvas
        }
    }

    private var branchHeader: some View {
        Group {
            if isCompactWidth {
                VStack(alignment: .leading, spacing: 10) {
                    branchSummary
                    gitActions
                }
            } else {
                HStack(spacing: 12) {
                    branchSummary
                    Spacer(minLength: 8)
                    gitActions
                }
            }
        }
    }

    private var branchSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(gitViewModel.branch.isEmpty ? "—" : gitViewModel.branch)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                if gitViewModel.ahead > 0 || gitViewModel.behind > 0 {
                    Text("\(gitViewModel.behind) behind  ·  \(gitViewModel.ahead) ahead")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                } else {
                    Text("Up to date")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var gitActions: some View {
        HStack(spacing: 8) {
                gitButton("Fetch", icon: "arrow.down.circle") { gitViewModel.fetch() }
                gitButton("Pull", icon: "arrow.triangle.merge") { gitViewModel.pull() }
                gitButton("Push", icon: "arrow.up.circle") { gitViewModel.push() }
        }
    }

    private func gitButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(minWidth: 58)
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
                        Section {
                            ForEach(staged) { entry in
                                fileRow(entry)
                                    .macOverlayScrollerStyle(entry.id == staged.first?.id)
                            }
                        } header: {
                            changesSectionHeader(title: "Staged", count: staged.count, tint: .green)
                        }
                    }
                    if !unstaged.isEmpty {
                        Section {
                            ForEach(unstaged) { entry in
                                fileRow(entry)
                                    .macOverlayScrollerStyle(
                                        staged.isEmpty && entry.id == unstaged.first?.id
                                    )
                            }
                        } header: {
                            changesSectionHeader(title: "Changes", count: unstaged.count, tint: .orange)
                        }
                    }
                    if !gitViewModel.commits.isEmpty {
                        Section("Recent Commits") {
                            ForEach(gitViewModel.commits) { commit in
                                commitRow(commit)
                                    .macOverlayScrollerStyle(
                                        staged.isEmpty && unstaged.isEmpty && commit.id == gitViewModel.commits.first?.id
                                    )
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private var historyList: some View {
        Group {
            if gitViewModel.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No commits were found for this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("Branch History") {
                        ForEach(gitViewModel.history) { entry in
                            Button {
                                selectedHistoryHash = entry.hash
                                openCommitDiff(entry)
                            } label: {
                                historyRow(entry, isSelected: selectedHistoryHash == entry.hash)
                                    .macOverlayScrollerStyle(entry.id == gitViewModel.history.first?.id)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                    Section("Commit Detail") {
                        if gitViewModel.isPreparingCommitDiff {
                            ProgressView("Preparing diff…")
                        } else if gitViewModel.isLoadingCommitDetail {
                            ProgressView("Loading commit…")
                        } else if let detail = gitViewModel.selectedCommitDetail {
                            commitDetailView(detail)
                        } else if let message = gitViewModel.statusMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.red)
                        } else {
                            Text("Select a commit to inspect its parents, message, and changed files.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollIndicators(.automatic)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private var graphCanvas: some View {
        Group {
            if gitViewModel.history.isEmpty {
                ContentUnavailableView(
                    "No Graph",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    description: Text("No branch graph is available for this repository.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 12) {
                        GitHistoryGraphCanvas(
                            entries: gitViewModel.history,
                            selectedHash: gitViewModel.selectedCommitDetail?.hash,
                            onSelect: { entry in openCommitDiff(entry) }
                        )
                        if gitViewModel.isPreparingCommitDiff {
                            ProgressView("Preparing diff…")
                                .padding(.horizontal, 16)
                        } else if gitViewModel.isLoadingCommitDetail {
                            ProgressView("Loading commit…")
                                .padding(.horizontal, 16)
                        } else if let detail = gitViewModel.selectedCommitDetail {
                            commitDetailView(detail)
                                .frame(width: 520, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                        } else if let message = gitViewModel.statusMessage {
                            Text(message)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.automatic)
                .background(Color.clear)
                .macOverlayScrollerStyle(transparentBackground: translucentBackgroundEnabled)
            }
        }
    }

    // MARK: - Row and Detail Views

    private func changesSectionHeader(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(tint.opacity(0.12), in: Capsule())
            Spacer()
        }
        .textCase(nil)
        .padding(.top, 8)
    }

    private func fileRow(_ entry: GitFileEntry) -> some View {
        let pathParts = gitPathParts(entry.path)
        return HStack(spacing: 10) {
            Image(systemName: entry.status.displayIcon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(gitStatusColor(for: entry.status))
                .frame(width: 26, height: 26)
                .background(gitStatusColor(for: entry.status).opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Button {
                    loadAndShowDiff(for: entry)
                } label: {
                    Text(pathParts.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(entry.status == .untracked)

                if let directory = pathParts.directory {
                    Text(directory)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(gitStatusLabel(for: entry.status))
                .font(.caption2.weight(.bold))
                .foregroundStyle(gitStatusColor(for: entry.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(gitStatusColor(for: entry.status).opacity(0.12), in: Capsule())

            Menu {
                if entry.staged {
                    Button("Unstage", systemImage: "minus.circle") {
                        gitViewModel.unstage(entry.path)
                    }
                } else {
                    Button("Stage", systemImage: "plus.circle") {
                        gitViewModel.stage(entry.path)
                    }
                }
                if entry.status != .untracked {
                    Button("Show Diff", systemImage: "rectangle.split.2x1") {
                        loadAndShowDiff(for: entry)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(entry.path)")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            if entry.staged {
                Button("Unstage", systemImage: "minus.circle") {
                    gitViewModel.unstage(entry.path)
                }
            } else {
                Button("Stage", systemImage: "plus.circle") {
                    gitViewModel.stage(entry.path)
                }
            }
            if entry.status != .untracked {
                Button("Show Diff", systemImage: "rectangle.split.2x1") {
                    loadAndShowDiff(for: entry)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gitStatusLabel(for: entry.status)), \(entry.staged ? "staged" : "unstaged"), \(entry.path)")
    }

    private func gitPathParts(_ path: String) -> (directory: String?, name: String) {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard let name = components.last else { return (nil, path) }
        let directory = components.dropLast().joined(separator: "/")
        return (directory.isEmpty ? nil : directory, String(name))
    }

    private func gitStatusColor(for status: GitFileStatus) -> Color {
        switch status {
        case .added, .untracked, .copied:
            .green
        case .modified, .renamed:
            .orange
        case .deleted, .conflicted:
            .red
        case .clean:
            .secondary
        }
    }

    private func gitStatusLabel(for status: GitFileStatus) -> String {
        switch status {
        case .modified: "Modified"
        case .added: "Added"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .conflicted: "Conflict"
        case .untracked: "New"
        case .clean: "Clean"
        }
    }

    private func historyRow(_ entry: GitHistoryEntry, isSelected: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isSelected ? Color.accentColor : .clear)
                .frame(width: 3)
                .accessibilityHidden(true)
            Text(entry.graph)
                .font(.caption.monospaced())
                .foregroundStyle(isSelected ? Color.accentColor : (entry.isMerge ? Color.orange : Color.secondary))
                .frame(width: 24, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.shortHash)
                        .font(.caption.monospaced())
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Text(entry.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
                HStack(spacing: 5) {
                    Text(entry.author)
                    Text(entry.date, style: .relative)
                    if entry.isMerge {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                    ForEach(entry.decorations.prefix(1), id: \.self) { decoration in
                        Text(decoration)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            changeStatView(entry)
            Label("Diff", systemImage: "square.split.2x1")
                .font(.caption.weight(.semibold))
                .labelStyle(.iconOnly)
                .foregroundStyle(.tint)
                .accessibilityLabel("Open Diff")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .frame(minHeight: 42)
        .padding(.vertical, 2)
        .padding(.leading, 4)
        .background(isSelected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(alignment: .trailing) {
            if isSelected {
                Label("Open", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .labelStyle(.iconOnly)
                    .padding(.trailing, 6)
                    .accessibilityLabel("Currently open")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(historyAccessibilityLabel(for: entry))
    }

    private func historyAccessibilityLabel(for entry: GitHistoryEntry) -> String {
        let decorations = entry.decorations.isEmpty ? "" : ", \(entry.decorations.joined(separator: ", "))"
        let merge = entry.isMerge ? "Merge commit, " : ""
        let stat = entry.hasChangeStat ? ", plus \(entry.insertions), minus \(entry.deletions)" : ""
        return "\(merge)\(entry.shortHash)\(decorations), \(entry.message), by \(entry.author)\(stat). Opens commit diff."
    }

    @ViewBuilder
    private func changeStatView(_ entry: GitHistoryEntry) -> some View {
        if entry.hasChangeStat {
            HStack(spacing: 0) {
                Text("+\(entry.insertions)")
                    .foregroundStyle(.green)
                Text("−\(entry.deletions)")
                    .foregroundStyle(.red)
            }
            .font(.caption.monospaced().weight(.semibold))
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }

    private func commitDetailView(_ detail: GitCommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(detail.shortHash)
                    .font(.caption.monospaced().weight(.semibold))
                if detail.isMerge {
                    Label("Merge", systemImage: "arrow.triangle.merge")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                ForEach(detail.decorations.prefix(3), id: \.self) { decoration in
                    Text(decoration)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(detail.subject)
                .font(.headline)
                .lineLimit(3)
            if !detail.body.isEmpty, detail.body != detail.subject {
                Text(detail.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
            }
            detailMetaGrid(detail)
            if !detail.shortStat.isEmpty {
                Text(detail.shortStat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !detail.files.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Changed Files")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(detail.files.prefix(24)) { file in
                        fileChangeRow(file)
                    }
                    if detail.files.count > 24 {
                        Text("+ \(detail.files.count - 24) more files")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Commit \(detail.shortHash), \(detail.subject), by \(detail.author)")
    }

    private func detailMetaGrid(_ detail: GitCommitDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Author: \(detail.author) <\(detail.email)>")
            Text("Date: \(detail.date.formatted(date: .abbreviated, time: .shortened))")
            if !detail.parentHashes.isEmpty {
                Text("Parents: \(detail.parentHashes.map { String($0.prefix(7)) }.joined(separator: ", "))")
            }
            Text("Full hash: \(detail.hash)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    private func fileChangeRow(_ file: GitCommitFileChange) -> some View {
        HStack(spacing: 8) {
            Text(file.status)
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(fileStatusColor(file.status))
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let previousPath = file.previousPath {
                    Text(previousPath)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Text(file.path)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    Text(file.path)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
    }

    private func fileStatusColor(_ status: String) -> Color {
        if status.hasPrefix("A") { return .green }
        if status.hasPrefix("D") { return .red }
        if status.hasPrefix("R") { return .orange }
        return .secondary
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

    // MARK: - Git Actions

    private func submitCommit() {
        let msg = commitMessage.trimmingCharacters(in: .whitespaces)
        guard !msg.isEmpty else { return }
        guard gitViewModel.entries.contains(where: \.staged) else { return }
        pendingCommit = GitCommitPreview(message: msg)
    }

    private func loadAndShowDiff(for entry: GitFileEntry) {
        guard let fileURL = gitViewModel.fileURL(for: entry.path) else { return }
        Task { @MainActor in
            let content = await Task.detached { () -> String in
                (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            }.value
            let diff = await Task.detached(priority: .userInitiated) {
                DocumentDiffBuilder.build(leftContent: "", rightContent: content)
            }.value
            inlineDiff = DocumentDiffPresentation(
                title: entry.path,
                leftTitle: "Empty",
                rightTitle: "Working Copy",
                diff: diff,
                language: LanguageDetector.shared.preferredLanguage(for: fileURL)
            )
        }
    }

    private func openCommitDiff(_ entry: GitHistoryEntry) {
        selectedHistoryHash = entry.hash
        Task { @MainActor in
            guard let diff = await gitViewModel.prepareCommitDiff(for: entry) else { return }
            let documentDiff = await Task.detached(priority: .userInitiated) {
                DocumentDiffBuilder.build(leftContent: diff.leftContent, rightContent: diff.rightContent)
            }.value
            inlineDiff = DocumentDiffPresentation(
                title: diff.title,
                leftTitle: diff.leftTitle,
                rightTitle: diff.rightTitle,
                diff: documentDiff,
                language: languageForCommitDiff(diff.rightContent)
            )
        }
    }

    private func selectLatestCommitIfNeeded() {
        guard inlineDiff == nil, let latest = gitViewModel.history.first else { return }
        openCommitDiff(latest)
    }
}

// MARK: - Inline Diff

private func languageForCommitDiff(_ content: String) -> String? {
    guard let header = content.split(separator: "\n", omittingEmptySubsequences: true).first(where: { $0.hasPrefix("--- ") }) else {
        return "standard"
    }
    let descriptor = header.dropFirst(4).drop { $0 == "A" || $0 == "M" || $0 == "D" || $0 == "R" || $0 == " " }
    let path = String(descriptor).components(separatedBy: " -> ").last ?? String(descriptor)
    return LanguageDetector.shared.preferredLanguage(for: URL(fileURLWithPath: path)) ?? "standard"
}

private enum DiffDisplayMode: String, Equatable {
    case inline
    case sideBySide
}

private enum UnifiedLineSide {
    case removed
    case inserted
}

private enum InlineDiffDisplayRow: Identifiable {
    case fileHeader(DocumentDiff.Row)
    case changeLine(DocumentDiff.Row)
    case unifiedLine(DocumentDiff.Row, UnifiedLineSide)
    case unchanged(Int, Int)

    var id: String {
        switch self {
        case .fileHeader(let row): "file-\(row.id)"
        case .changeLine(let row): "change-\(row.id)"
        case .unifiedLine(let row, let side): "unified-\(row.id)-\(side == .removed ? "removed" : "inserted")"
        case .unchanged(let index, let count): "unchanged-\(index)-\(count)"
        }
    }
}

struct InlineDiffView: View {
    let presentation: DocumentDiffPresentation
    let translucentBackgroundEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("DiffDisplayMode") private var storedDisplayModeRaw: String = DiffDisplayMode.sideBySide.rawValue
    @State private var displayMode: DiffDisplayMode
    @State private var selectedChangeIndex: Int = 0

    init(
        presentation: DocumentDiffPresentation,
        translucentBackgroundEnabled: Bool = false
    ) {
        self.presentation = presentation
        self.translucentBackgroundEnabled = translucentBackgroundEnabled
        let storedRaw = UserDefaults.standard.string(forKey: "DiffDisplayMode") ?? DiffDisplayMode.sideBySide.rawValue
        _displayMode = State(initialValue: DiffDisplayMode(rawValue: storedRaw) ?? .sideBySide)
    }

    private var changedRows: [DocumentDiff.Row] {
        presentation.diff.rows.filter(\.isChanged)
    }

    private var isCompactWidth: Bool {
#if os(macOS)
        false
#else
        horizontalSizeClass == .compact
#endif
    }

    private var displayRows: [InlineDiffDisplayRow] {
        var result: [InlineDiffDisplayRow] = []
        var index = 0
        var unchangedGroupIndex = 0
        while index < presentation.diff.rows.count {
            let row = presentation.diff.rows[index]
            if case .equal = row.kind {
                if row.leftText.hasPrefix("--- ") {
                    result.append(.fileHeader(row))
                    index += 1
                    continue
                }
                var end = index
                while end < presentation.diff.rows.count {
                    guard case .equal = presentation.diff.rows[end].kind else { break }
                    end += 1
                }
                let unchangedRows = Array(presentation.diff.rows[index..<end])
                if unchangedRows.count > 2 {
                    result.append(.unchanged(unchangedGroupIndex, unchangedRows.count))
                    unchangedGroupIndex += 1
                } else {
                    result.append(contentsOf: unchangedRows.map { .changeLine($0) })
                }
                index = end
            } else {
                var end = index
                while end < presentation.diff.rows.count {
                    if case .equal = presentation.diff.rows[end].kind { break }
                    end += 1
                }
                let changedRows = Array(presentation.diff.rows[index..<end])
                if displayMode == .inline {
                    result.append(contentsOf: changedRows.filter { $0.leftLineNumber != nil }.map { .unifiedLine($0, .removed) })
                    result.append(contentsOf: changedRows.filter { $0.rightLineNumber != nil }.map { .unifiedLine($0, .inserted) })
                } else {
                    result.append(contentsOf: changedRows.map { .changeLine($0) })
                }
                index = end
            }
        }
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                header(scrollTo: { rowID in
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo("change-\(rowID)", anchor: .center)
                        }
                    }
                })
                Divider()
                GeometryReader { geometry in
                    let availableWidth = max(0, geometry.size.width - 24)
                    let isInline = displayMode == .inline
                    let contentWidth: CGFloat = isInline
                        ? max(320, availableWidth)
                        : max(642, availableWidth)
                    diffRowsView(contentWidth: contentWidth, isInline: isInline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.clear)
            .onChange(of: selectedChangeIndex) { _, newIndex in
                guard changedRows.indices.contains(newIndex) else { return }
                let rowID = changedRows[newIndex].id
                DispatchQueue.main.async {
                    proxy.scrollTo("change-\(rowID)", anchor: .center)
                }
            }
        }
        .background(Color.clear)
        .task {
            if UserDefaults.standard.object(forKey: "DiffDisplayMode") == nil {
                displayMode = isCompactWidth ? .inline : .sideBySide
            }
        }
        .onChange(of: displayMode) { _, newMode in
            storedDisplayModeRaw = newMode.rawValue
        }
        .onChange(of: presentation.id) { _, _ in
            selectedChangeIndex = 0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.title), comparing \(presentation.leftTitle) with \(presentation.rightTitle)")
    }

    private func displayRowView(
        _ row: InlineDiffDisplayRow,
        isInline: Bool,
        width: CGFloat
    ) -> AnyView {
        switch row {
        case .fileHeader(let row):
            return AnyView(fileHeaderRow(row, minWidth: width))
        case .changeLine(let row):
            if isInline {
                return AnyView(unifiedDiffRow(row, minWidth: width))
            } else {
                return AnyView(diffRow(row, width: width))
            }
        case .unifiedLine(let row, let side):
            return AnyView(unifiedDiffLine(row, side: side, minWidth: width))
        case .unchanged(_, let count):
            return AnyView(unchangedRow(count, minWidth: width))
        }
    }

    private func diffRowsView(contentWidth: CGFloat, isInline: Bool) -> AnyView {
        let axes: Axis.Set = isInline ? .vertical : [.horizontal, .vertical]
        let rows: [InlineDiffDisplayRow] = displayRows
        let scrollView = ScrollView(axes) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    displayRowView(rows[index], isInline: isInline, width: contentWidth)
                }
            }
            .padding(12)
        }
        .background(Color.clear)
        .macOverlayScrollerStyle(transparentBackground: translucentBackgroundEnabled)
        return AnyView(scrollView)
    }

    private func header(scrollTo: @escaping (Int) -> Void) -> some View {
        Group {
            if isCompactWidth {
                VStack(alignment: .leading, spacing: 8) {
                    titleAndNavigation(scrollTo: scrollTo)
                    sourceBadges
                    displayModePicker
                }
            } else {
                HStack(spacing: 10) {
                    titleAndNavigation(scrollTo: scrollTo)
                        .frame(maxWidth: 250, alignment: .leading)
                    sourceBadges
                    Spacer(minLength: 4)
                    displayModePicker
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: isCompactWidth ? 128 : 64, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func titleAndNavigation(scrollTo: @escaping (Int) -> Void) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(presentation.diff.hunks.count) change\(presentation.diff.hunks.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if !changedRows.isEmpty {
                Button {
                    selectedChangeIndex = max(0, selectedChangeIndex - 1)
                    scrollTo(changedRows[selectedChangeIndex].id)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(selectedChangeIndex == 0)
                .accessibilityLabel("Previous Change")
                Button {
                    selectedChangeIndex = min(changedRows.count - 1, selectedChangeIndex + 1)
                    scrollTo(changedRows[selectedChangeIndex].id)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(selectedChangeIndex >= changedRows.count - 1)
                .accessibilityLabel("Next Change")
                Text("\(selectedChangeIndex + 1)/\(changedRows.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceBadges: some View {
        HStack(spacing: 8) {
                sourceBadge(presentation.leftTitle, color: .red)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                sourceBadge(presentation.rightTitle, color: .green)
        }
    }

    private var displayModePicker: some View {
        Picker("Diff view", selection: $displayMode) {
                Label("Inline", systemImage: "text.alignleft").tag(DiffDisplayMode.inline)
                Label("Side by Side", systemImage: "rectangle.split.2x1").tag(DiffDisplayMode.sideBySide)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minWidth: 150)
        .accessibilityLabel("Diff view")
    }

    private func sourceBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(colorScheme == .dark ? 0.18 : 0.10), in: Capsule())
    }

    private func fileHeaderRow(_ row: DocumentDiff.Row, minWidth: CGFloat) -> some View {
        let descriptor = row.leftText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .dropFirst(4)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        let parts = descriptor.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let status = parts.first.map(String.init) ?? "M"
        let path = parts.dropFirst().first.map(String.init) ?? descriptor
        let statusColor = status.hasPrefix("A") ? Color.green : status.hasPrefix("D") ? .red : status.hasPrefix("R") ? .orange : .secondary

        return HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.tint)
            Text(path)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(status)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(statusColor)
        }
        .frame(width: minWidth, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(colorScheme == .dark ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("File \(path), status \(status)")
    }

    private func diffRow(_ row: DocumentDiff.Row, width: CGFloat) -> some View {
        let columnWidth = max(320, (width - 1) / 2)
        return HStack(alignment: .top, spacing: 0) {
            diffCell(lineNumber: row.leftLineNumber, text: row.leftText, color: leftColor(for: row), width: columnWidth)
            Divider()
            diffCell(lineNumber: row.rightLineNumber, text: row.rightText, color: rightColor(for: row), width: columnWidth)
        }
        .frame(width: width, alignment: .leading)
        .id("change-\(row.id)")
        .background(rowBackground(for: row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(for: row))
    }

    private func unchangedRow(_ count: Int, minWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
            Text("\(count) unchanged lines")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(width: minWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityLabel("\(count) unchanged lines")
    }

    private func unifiedDiffRow(_ row: DocumentDiff.Row, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if case .removed = row.kind {
                unifiedLine(prefix: "−", lineNumber: row.leftLineNumber, text: row.leftText, color: .red)
            }
            if case .changed = row.kind {
                unifiedLine(prefix: "−", lineNumber: row.leftLineNumber, text: row.leftText, color: .red)
                unifiedLine(prefix: "+", lineNumber: row.rightLineNumber, text: row.rightText, color: .green)
            } else if case .inserted = row.kind {
                unifiedLine(prefix: "+", lineNumber: row.rightLineNumber, text: row.rightText, color: .green)
            }
            if case .equal = row.kind {
                unifiedLine(prefix: " ", lineNumber: row.rightLineNumber ?? row.leftLineNumber, text: row.rightText, color: .secondary)
            }
        }
        .frame(width: minWidth, alignment: .leading)
        .id("change-\(row.id)")
        .background(rowBackground(for: row))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel(for: row))
    }

    private func unifiedDiffLine(
        _ row: DocumentDiff.Row,
        side: UnifiedLineSide,
        minWidth: CGFloat
    ) -> some View {
        let isRemoved = side == .removed
        return unifiedLine(
            prefix: isRemoved ? "−" : "+",
            lineNumber: isRemoved ? row.leftLineNumber : row.rightLineNumber,
            text: isRemoved ? row.leftText : row.rightText,
            color: isRemoved ? .red : .green
        )
        .frame(width: minWidth, alignment: .leading)
        .id("unified-\(row.id)-\(isRemoved ? "removed" : "inserted")")
        .accessibilityLabel("\(isRemoved ? "removed" : "inserted"), \(rowAccessibilityLabel(for: row))")
    }

    private func unifiedLine(prefix: String, lineNumber: Int?, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(color)
                .frame(width: 16, alignment: .center)
            Text(lineNumber.map(String.init) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
            SyntaxHighlightedDiffText(text: text.isEmpty ? " " : text, language: presentation.language)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(colorScheme == .dark ? 0.20 : 0.11))
    }

    private func diffCell(lineNumber: Int?, text: String, color: Color?, width: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(color ?? .clear)
                .frame(width: 3)
                .accessibilityHidden(true)
            Text(lineNumber.map(String.init) ?? "")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
                .accessibilityHidden(true)
            SyntaxHighlightedDiffText(text: text.isEmpty ? " " : text, language: presentation.language)
                .textSelection(.enabled)
                .frame(width: max(0, width - 58), alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
        .background(color.map { $0.opacity(colorScheme == .dark ? 0.20 : 0.11) } ?? .clear)
    }

    private func leftColor(for row: DocumentDiff.Row) -> Color? {
        switch row.kind {
        case .removed, .changed: .red
        case .equal, .inserted: nil
        }
    }

    private func rightColor(for row: DocumentDiff.Row) -> Color? {
        switch row.kind {
        case .inserted, .changed: .green
        case .equal, .removed: nil
        }
    }

    private func rowBackground(for row: DocumentDiff.Row) -> Color {
        .clear
    }

    private func rowAccessibilityLabel(for row: DocumentDiff.Row) -> String {
        let kind: String
        switch row.kind {
        case .equal: kind = "unchanged"
        case .removed: kind = "removed"
        case .inserted: kind = "inserted"
        case .changed: kind = "changed"
        }
        return "\(kind), left line \(row.leftLineNumber.map(String.init) ?? "none"), right line \(row.rightLineNumber.map(String.init) ?? "none")"
    }
}

private struct SyntaxHighlightedDiffText: View {
    let text: String
    let language: String?
    @Environment(\.colorScheme) private var colorScheme

    private var highlightedText: AttributedString {
        cachedDiffSyntax(text: text, language: language, colorScheme: colorScheme)
    }

    var body: some View {
        Text(highlightedText)
            .font(.caption.monospaced())
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum DiffSyntaxCache {
    static let storage = NVELock<[String: AttributedString]>([:])
    static let maxEntries = 4096
}

private func cachedDiffSyntax(
    text: String,
    language: String?,
    colorScheme: ColorScheme
) -> AttributedString {
    guard let language, !language.isEmpty, language.lowercased() != "plain" else {
        return AttributedString(text)
    }

    let colors = SyntaxColors.from(theme: currentEditorTheme(colorScheme: colorScheme))
    let themeKey = [
        colors.keyword, colors.string, colors.number, colors.comment,
        colors.attribute, colors.variable, colors.def, colors.property,
        colors.meta, colors.tag, colors.atom, colors.builtin, colors.type
    ].map(colorToHex).joined(separator: ",")
    let key = "\(language.lowercased())|\(themeKey)|\(text)"
    if let cached = DiffSyntaxCache.storage.withLock({ $0[key] }) {
        return cached
    }

    var attributed = AttributedString(text)
    let patterns = getSyntaxPatterns(for: language, colors: colors, profile: .full)
    let sourceRange = NSRange(text.startIndex..<text.endIndex, in: text)
    for (pattern, color) in patterns {
        guard let regex = cachedSyntaxRegex(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
        for match in regex.matches(in: text, options: [], range: sourceRange) {
            guard match.range.location != NSNotFound, match.range.length > 0 else { continue }
            let start = attributed.index(attributed.startIndex, offsetByCharacters: match.range.location)
            let end = attributed.index(start, offsetByCharacters: match.range.length)
            attributed[start..<end].foregroundColor = color
        }
    }

    DiffSyntaxCache.storage.withLock { cache in
        if cache.count >= DiffSyntaxCache.maxEntries {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = attributed
    }
    return attributed
}

struct DiffEditorSurface: View {
    let presentation: DocumentDiffPresentation
    let onClose: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isCompact: Bool {
#if os(macOS)
        false
#else
        horizontalSizeClass == .compact
#endif
    }

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: 0) {
                    outline
                        .frame(maxHeight: 220)
                    Divider()
                    InlineDiffView(presentation: presentation)
                }
            } else {
                HStack(spacing: 0) {
                    outline
                        .frame(minWidth: 340, idealWidth: 400, maxWidth: 480)
                        .layoutPriority(1)
                    Divider()
                    InlineDiffView(presentation: presentation)
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Diff editor for \(presentation.title)")
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compare")
                        .font(.headline.weight(.semibold))
                    Text(presentation.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                Button(action: onClose) {
                    Label("Close Diff", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Close Diff")
            }
            .padding(14)
            Divider()
            HStack(spacing: 6) {
                Text(presentation.leftTitle)
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(presentation.rightTitle)
                    .foregroundStyle(.green)
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            if !isCompact {
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(presentation.changedRows) { row in
                            changedRow(row)
                        }
                        if presentation.changedRows.isEmpty {
                            ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 140)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .background(Color.clear)
    }

    private func changedRow(_ row: DocumentDiff.Row) -> some View {
        let color: Color
        let icon: String
        switch row.kind {
        case .removed:
            color = .red
            icon = "minus"
        case .inserted:
            color = .green
            icon = "plus"
        case .changed:
            color = .orange
            icon = "arrow.left.arrow.right"
        case .equal:
            color = .secondary
            icon = "circle"
        }
        let summaryText = row.rightText.isEmpty ? row.leftText : row.rightText
        return HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.leftLineNumber.map { "L\($0)" } ?? row.rightLineNumber.map { "R\($0)" } ?? "")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(color)
                Text(summaryText.isEmpty ? " " : summaryText)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Git History Graph

private struct GitHistoryGraphCanvas: View {
    let entries: [GitHistoryEntry]
    let selectedHash: String?
    let onSelect: (GitHistoryEntry) -> Void

    private let rowHeight: CGFloat = 46
    private let laneWidth: CGFloat = 22
    private let graphWidth: CGFloat = 126
    private let cardWidth: CGFloat = 430

    private var canvasSize: CGSize {
        CGSize(width: graphWidth + cardWidth + 32, height: CGFloat(entries.count) * rowHeight + 24)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawGraph(in: context)
            }
            .frame(width: canvasSize.width, height: canvasSize.height)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 8) {
                        Text(entry.shortHash)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.message)
                                .font(.caption)
                                .lineLimit(1)
                            Text(graphSubtitle(for: entry))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        changeStatView(entry)
                        if entry.isMerge {
                            Image(systemName: "arrow.triangle.merge")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: cardWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(entry.hash == selectedHash ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .position(x: graphWidth + (cardWidth / 2), y: rowY(index))
                .accessibilityLabel(graphAccessibilityLabel(for: entry))
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visual branch graph")
    }

    private func graphSubtitle(for entry: GitHistoryEntry) -> String {
        "\(entry.author) · \(entry.date.formatted(date: .omitted, time: .shortened))"
    }

    private func graphAccessibilityLabel(for entry: GitHistoryEntry) -> String {
        let stat = entry.hasChangeStat ? ", plus \(entry.insertions), minus \(entry.deletions)" : ""
        return "Graph commit \(entry.shortHash), \(entry.message), by \(entry.author)\(stat). Opens commit diff."
    }

    @ViewBuilder
    private func changeStatView(_ entry: GitHistoryEntry) -> some View {
        if entry.hasChangeStat {
            HStack(spacing: 0) {
                Text("+\(entry.insertions)")
                    .foregroundStyle(.green)
                Text("−\(entry.deletions)")
                    .foregroundStyle(.red)
            }
            .font(.caption.monospaced().weight(.semibold))
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }

    private func drawGraph(in context: GraphicsContext) {
        guard entries.isEmpty == false else { return }
        let lanes = entries.map { laneIndex(for: $0.graph) }

        for index in entries.indices.dropLast() {
            let currentLane = lanes[index]
            let nextLane = lanes[index + 1]
            let start = CGPoint(x: laneX(currentLane), y: rowY(index) + 8)
            let end = CGPoint(x: laneX(nextLane), y: rowY(index + 1) - 8)
            var path = Path()
            path.move(to: start)
            if currentLane == nextLane {
                path.addLine(to: end)
            } else {
                let midY = (start.y + end.y) / 2
                path.addCurve(
                    to: end,
                    control1: CGPoint(x: start.x, y: midY),
                    control2: CGPoint(x: end.x, y: midY)
                )
            }
            context.stroke(path, with: .color(.secondary.opacity(0.45)), lineWidth: 1.5)
        }

        for (index, entry) in entries.enumerated() {
            let point = CGPoint(x: laneX(lanes[index]), y: rowY(index))
            let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            context.fill(Path(ellipseIn: rect), with: .color(entry.isMerge ? .orange : .accentColor))
            if entry.hash == selectedHash {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -5, dy: -5)), with: .color(.accentColor), lineWidth: 2)
            }
        }
    }

    private func laneIndex(for graph: String) -> Int {
        guard let marker = graph.firstIndex(of: "*") else { return 0 }
        let distance = graph.distance(from: graph.startIndex, to: marker)
        return max(0, min(4, distance / 2))
    }

    private func laneX(_ lane: Int) -> CGFloat {
        18 + (CGFloat(lane) * laneWidth)
    }

    private func rowY(_ index: Int) -> CGFloat {
        18 + (CGFloat(index) * rowHeight)
    }
}

import SwiftUI

// MARK: - Git Sidebar Tab

private enum GitTabSection: String, CaseIterable, Identifiable {
    case changes = "Changes"
    case history = "History"
    case graph = "Graph"

    var id: String { rawValue }
}

struct GitTabView: View {
    @State var gitViewModel: GitViewModel
    let onShowDiff: (@MainActor (String, String, String, String, String) -> Void)?
    let translucentBackgroundEnabled: Bool
    @State private var commitMessage: String = ""
    @State private var selectedSection: GitTabSection = .changes
    @Environment(\.colorScheme) private var colorScheme
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif

    init(
        gitViewModel: GitViewModel,
        translucentBackgroundEnabled: Bool = false,
        onShowDiff: (@MainActor (String, String, String, String, String) -> Void)? = nil
    ) {
        self.gitViewModel = gitViewModel
        self.translucentBackgroundEnabled = translucentBackgroundEnabled
        self.onShowDiff = onShowDiff
    }

    private var surfaceBackground: AnyShapeStyle {
        if translucentBackgroundEnabled {
#if os(macOS)
            switch macTranslucencyModeRaw {
            case "subtle":
                return AnyShapeStyle(.thickMaterial.opacity(0.70))
            case "vibrant":
                return AnyShapeStyle(.regularMaterial.opacity(0.46))
            default:
                return AnyShapeStyle(.thickMaterial.opacity(0.58))
            }
#else
            return AnyShapeStyle(.ultraThinMaterial)
#endif
        }
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !gitViewModel.isRepo {
                gitSetupView
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
                sectionPicker
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                Divider()
                selectedContent
                if selectedSection == .changes {
                    Divider()
                    commitBar
                        .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(surfaceBackground)
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
        VStack(alignment: .leading, spacing: 10) {
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
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                gitButton("Fetch", icon: "arrow.down.circle") { gitViewModel.fetch() }
                gitButton("Pull", icon: "arrow.triangle.merge") { gitViewModel.pull() }
                gitButton("Push", icon: "arrow.up.circle") { gitViewModel.push() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                                openCommitDiff(entry)
                            } label: {
                                historyRow(entry)
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
                .listStyle(.inset)
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
                .background(Color.clear)
            }
        }
    }

    // MARK: - Row and Detail Views

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

    private func historyRow(_ entry: GitHistoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.graph)
                .font(.caption.monospaced())
                .foregroundStyle(entry.isMerge ? .orange : .secondary)
                .frame(width: 42, alignment: .leading)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.shortHash)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    if entry.isMerge {
                        Label("Merge", systemImage: "arrow.triangle.merge")
                            .font(.caption2)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.orange)
                    }
                    ForEach(entry.decorations.prefix(2), id: \.self) { decoration in
                        Text(decoration)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Text(entry.message)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(entry.author)
                    Text(entry.date, style: .relative)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            changeStatView(entry)
            Label("Diff", systemImage: "square.split.2x1")
                .font(.caption2.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
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
        gitViewModel.commit(message: msg)
        commitMessage = ""
    }

    private func loadAndShowDiff(for entry: GitFileEntry) {
        guard let onShowDiff, let fileURL = gitViewModel.fileURL(for: entry.path) else { return }
        Task { @MainActor in
            let content = await Task.detached { () -> String in
                (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            }.value
            onShowDiff(entry.path, "Working", "Disk", "", content)
        }
    }

    private func openCommitDiff(_ entry: GitHistoryEntry) {
        guard let onShowDiff else {
            gitViewModel.selectHistoryEntry(entry)
            return
        }
        Task { @MainActor in
            guard let diff = await gitViewModel.prepareCommitDiff(for: entry) else { return }
            onShowDiff(diff.title, diff.leftTitle, diff.rightTitle, diff.leftContent, diff.rightContent)
        }
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

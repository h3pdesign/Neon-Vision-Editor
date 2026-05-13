import SwiftUI

struct FolderComparison: Identifiable {
    let id = UUID()
    let added: [FolderCompareFile]
    let removed: [FolderCompareFile]
    let modified: [FolderCompareFile]
    let unchanged: [FolderCompareFile]

    var totalChanges: Int { added.count + removed.count + modified.count }
}

struct FolderCompareFile: Identifiable, Hashable {
    let relativePath: String
    let leftURL: URL?
    let rightURL: URL?
    let leftModDate: Date?
    let rightModDate: Date?
    var id: String { relativePath }
}

enum FolderCompareFilter: String, CaseIterable {
    case all = "All"
    case added = "Added"
    case removed = "Removed"
    case modified = "Modified"
}

struct FolderCompareView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let onOpenFile: (URL) -> Void
    let onShowDiff: (DocumentDiffPresentation) -> Void

    @State private var leftFolderURL: URL?
    @State private var rightFolderURL: URL?
    @State private var comparison: FolderComparison?
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var searchQuery = ""
    @State private var selectedFilter: FolderCompareFilter = .all
    @State private var selectedFile: FolderCompareFile?

    private let pageSize = 50
    @State private var currentPage = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comparison == nil {
                    folderSelectionView
                } else {
                    resultsView
                }
            }
            .background(editorSurfaceBackground)
#if os(macOS)
            .toolbarBackground(editorSurfaceBackground, for: .windowToolbar)
            .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
            .navigationTitle("Folder Compare")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if comparison != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Comparison") {
                            comparison = nil
                            leftFolderURL = nil
                            rightFolderURL = nil
                        }
                    }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
    }

    private var editorSurfaceBackground: Color {
        currentEditorTheme(colorScheme: colorScheme).background
    }

    private var folderSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                folderPickerRow(title: "Left Folder", url: $leftFolderURL)
                folderPickerRow(title: "Right Folder", url: $rightFolderURL)
            }
            .padding(.horizontal, 24)

            if let error = scanError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button(action: startComparison) {
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Compare Folders")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(leftFolderURL == nil || rightFolderURL == nil || isScanning)
            .controlSize(.large)

            Spacer()
        }
    }

    private func folderPickerRow(title: String, url: Binding<URL?>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .frame(width: 100, alignment: .leading)
            Text(url.wrappedValue?.lastPathComponent ?? "Not selected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Browse…") {
                selectFolder(url: url)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if url.wrappedValue != nil {
                Button { url.wrappedValue = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectFolder(url: Binding<URL?>) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { response in
            if response == .OK, let selected = panel.url {
                url.wrappedValue = selected
            }
        }
        #endif
    }

    private func startComparison() {
        guard let left = leftFolderURL, let right = rightFolderURL else { return }
        isScanning = true
        scanError = nil
        Task {
            let result = await Self.scanFolders(left: left, right: right)
            await MainActor.run {
                comparison = result
                isScanning = false
                currentPage = 0
            }
        }
    }

    private static func scanFolders(left: URL, right: URL) async -> FolderComparison {
        await Task.detached(priority: .userInitiated) {
            let didAccessLeft = left.startAccessingSecurityScopedResource()
            let didAccessRight = right.startAccessingSecurityScopedResource()
            defer {
                if didAccessRight { right.stopAccessingSecurityScopedResource() }
                if didAccessLeft { left.stopAccessingSecurityScopedResource() }
            }

            let leftFiles = Self.indexFolderContents(at: left)
            let rightFiles = Self.indexFolderContents(at: right)

            var added: [FolderCompareFile] = []
            var removed: [FolderCompareFile] = []
            var modified: [FolderCompareFile] = []
            var unchanged: [FolderCompareFile] = []
            for (relPath, leftInfo) in leftFiles {
                if let rightInfo = rightFiles[relPath] {
                    let isModified = leftInfo.modDate != rightInfo.modDate
                    let file = FolderCompareFile(
                        relativePath: relPath,
                        leftURL: leftInfo.url,
                        rightURL: rightInfo.url,
                        leftModDate: leftInfo.modDate,
                        rightModDate: rightInfo.modDate
                    )
                    if isModified { modified.append(file) }
                    else { unchanged.append(file) }
                } else {
                    removed.append(FolderCompareFile(
                        relativePath: relPath, leftURL: leftInfo.url, rightURL: nil,
                        leftModDate: leftInfo.modDate, rightModDate: nil
                    ))
                }
            }
            for (relPath, rightInfo) in rightFiles where !leftFiles.keys.contains(relPath) {
                added.append(FolderCompareFile(
                    relativePath: relPath, leftURL: nil, rightURL: rightInfo.url,
                    leftModDate: nil, rightModDate: rightInfo.modDate
                ))
            }

            let sortKey: (FolderCompareFile) -> String = { $0.relativePath }
            return FolderComparison(
                added: added.sorted { sortKey($0) < sortKey($1) },
                removed: removed.sorted { sortKey($0) < sortKey($1) },
                modified: modified.sorted { sortKey($0) < sortKey($1) },
                unchanged: unchanged.sorted { sortKey($0) < sortKey($1) }
            )
        }.value
    }

    struct FileInfo {
        let url: URL
        let modDate: Date?
    }

    nonisolated static func indexFolderContents(at root: URL) -> [String: FileInfo] {
        let fm = FileManager.default
        let rootPath = root.standardizedFileURL.path
        var result: [String: FileInfo] = [:]
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return result }
        for case let fileURL as URL in enumerator {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
            let filePath = fileURL.standardizedFileURL.path
            guard filePath.hasPrefix(rootPath) else { continue }
            let relPath = String(filePath.dropFirst(rootPath.count + 1))
            let modDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            result[relPath] = FileInfo(url: fileURL, modDate: modDate)
        }
        return result
    }

    private var resultsView: some View {
        VStack(spacing: 0) {
            summaryHeader
            filterAndSearchBar
            fileList
        }
    }

    private var summaryHeader: some View {
        guard let c = comparison else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 16) {
                statBadge(count: c.added.count, label: "Added", color: .green)
                statBadge(count: c.removed.count, label: "Removed", color: .red)
                statBadge(count: c.modified.count, label: "Modified", color: .orange)
                statBadge(count: c.unchanged.count, label: "Unchanged", color: .secondary)
                Spacer()
                Text("\(c.totalChanges) changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(editorSurfaceBackground.opacity(0.9))
        )
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }

    private var filterAndSearchBar: some View {
        HStack(spacing: 8) {
            Picker("Filter", selection: $selectedFilter) {
                ForEach(FolderCompareFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter files…", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 220)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var filteredFiles: [FolderCompareFile] {
        guard let c = comparison else { return [] }
        var files: [FolderCompareFile] = []
        switch selectedFilter {
        case .all:
            files = c.added + c.removed + c.modified
        case .added: files = c.added
        case .removed: files = c.removed
        case .modified: files = c.modified
        }
        if !searchQuery.isEmpty {
            files = files.filter { $0.relativePath.localizedCaseInsensitiveContains(searchQuery) }
        }
        return files
    }

    private var fileList: some View {
        let files = filteredFiles
        let pageFiles = Array(files.prefix((currentPage + 1) * pageSize))

        return Group {
            if files.isEmpty {
                ContentUnavailableView("No files match", systemImage: "magnifyingglass")
            } else {
                List {
                    ForEach(pageFiles) { file in
                        fileRow(file)
                    }
                    if pageFiles.count < files.count {
                        Button("Show more... (\(files.count - pageFiles.count) remaining)") {
                            currentPage += 1
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func fileRow(_ file: FolderCompareFile) -> some View {
        let isAdded = comparison?.added.contains(file) ?? false
        let isRemoved = comparison?.removed.contains(file) ?? false
        let isModified = comparison?.modified.contains(file) ?? false
        let statusColor: Color = isAdded ? .green : isRemoved ? .red : isModified ? .orange : .secondary
        let statusIcon = isAdded ? "plus.circle" : isRemoved ? "minus.circle" : isModified ? "pencil.circle" : "checkmark.circle"

        return Button {
            if isModified, let leftURL = file.leftURL, let rightURL = file.rightURL {
                selectedFile = file
                compareFiles(file, leftURL: leftURL, rightURL: rightURL)
            } else if let singleURL = file.leftURL ?? file.rightURL {
                openFile(singleURL)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.subheadline)
                Text(file.relativePath)
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                Spacer()
                if isAdded || isRemoved {
                    Text(isAdded ? "Added" : "Removed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func compareFiles(_ file: FolderCompareFile, leftURL: URL, rightURL: URL) {
        Task {
            let leftContent = (try? String(contentsOf: leftURL, encoding: .utf8)) ?? ""
            let rightContent = (try? String(contentsOf: rightURL, encoding: .utf8)) ?? ""
            let diff = await Task.detached(priority: .userInitiated) {
                DocumentDiffBuilder.build(leftContent: leftContent, rightContent: rightContent)
            }.value
            await MainActor.run {
                let presentation = DocumentDiffPresentation(
                    title: file.relativePath,
                    leftTitle: leftURL.lastPathComponent,
                    rightTitle: rightURL.lastPathComponent,
                    diff: diff
                )
                onShowDiff(presentation)
            }
        }
    }

    private func openFile(_ url: URL) {
        onOpenFile(url)
    }
}

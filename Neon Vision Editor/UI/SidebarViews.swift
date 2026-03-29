import SwiftUI
import Foundation

#if os(macOS)


/// MARK: - Types

private enum MacTranslucencyMode: String {
    case subtle
    case balanced
    case vibrant

    var material: Material {
        switch self {
        case .subtle, .balanced:
            return .thickMaterial
        case .vibrant:
            return .regularMaterial
        }
    }

    var opacity: Double {
        switch self {
        case .subtle: return 0.98
        case .balanced: return 0.93
        case .vibrant: return 0.90
        }
    }
}
#endif

struct SidebarView: View {
    private struct TOCItem: Identifiable, Hashable {
        let id: String
        let title: String
        let line: Int?
    }

    let content: String
    let language: String
    let translucentBackgroundEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif
    @State private var tocItems: [TOCItem] = [
        TOCItem(id: "empty", title: "No content available", line: nil)
    ]
    @State private var tocRefreshTask: Task<Void, Never>?

    var body: some View {
        List {
            ForEach(tocItems) { item in
                Button {
                    jump(to: item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(sidebarRowFill)
                        )
                }
                .buttonStyle(.plain)
                .disabled(item.line == nil)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(platformListStyle)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(sidebarOuterPaddingInsets)
        .background(
            RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                .fill(sidebarSurfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                        .stroke(sidebarSurfaceStroke, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
        .onAppear {
            scheduleTOCRefresh()
        }
        .onChange(of: content) { _, _ in
            scheduleTOCRefresh()
        }
        .onChange(of: language) { _, _ in
            scheduleTOCRefresh()
        }
        .onDisappear {
            tocRefreshTask?.cancel()
        }
    }

    private var sidebarSurfaceFill: AnyShapeStyle {
        if translucentBackgroundEnabled {
            #if os(macOS)
            let mode = MacTranslucencyMode(rawValue: macTranslucencyModeRaw) ?? .balanced
            return AnyShapeStyle(mode.material.opacity(mode.opacity))
            #else
            return AnyShapeStyle(.ultraThinMaterial)
            #endif
        }
#if os(macOS)
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
#else
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
#endif
    }

    private var sidebarSurfaceStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var platformListStyle: some ListStyle {
#if os(iOS)
        PlainListStyle()
#else
        SidebarListStyle()
#endif
    }

    private var sidebarRowFill: Color {
#if os(macOS)
        Color.secondary.opacity(0.10)
#else
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color(red: 0.80, green: 0.88, blue: 1.0).opacity(0.55)
#endif
    }

    private var sidebarOuterPaddingInsets: EdgeInsets {
#if os(iOS)
        EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
#else
        EdgeInsets()
#endif
    }

    private var sidebarCornerRadius: CGFloat {
#if os(macOS)
        0
#else
        14
#endif
    }

    private func jump(to item: TOCItem) {
        guard let lineOneBased = item.line, lineOneBased > 0 else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .moveCursorToLine, object: lineOneBased)
        }
    }

    private func scheduleTOCRefresh() {
        tocRefreshTask?.cancel()
        let snapshotContent = content
        let snapshotLanguage = language
        tocRefreshTask = Task(priority: .utility) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            let generated = SidebarView.generateTableOfContents(content: snapshotContent, language: snapshotLanguage)
            await MainActor.run {
                tocItems = generated
            }
        }
    }

    // Naive line-scanning TOC: looks for language-specific declarations or headers.
    private static func generateTableOfContents(content: String, language: String) -> [TOCItem] {
        guard !content.isEmpty else {
            return [TOCItem(id: "empty", title: "No content available", line: nil)]
        }
        if (content as NSString).length >= 400_000 {
            return [TOCItem(id: "large", title: "Large file detected: TOC disabled for performance", line: nil)]
        }
        let lines = content.components(separatedBy: .newlines)
        var toc: [TOCItem] = []

        switch language {
        case "swift":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") ||
                   trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") {
                    return TOCItem(id: "swift-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "python":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") {
                    return TOCItem(id: "python-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "javascript":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") {
                    return TOCItem(id: "js-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "java":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || (t.contains(" void ") || (t.contains(" public ") && t.contains("(") && t.contains(")"))) {
                    return TOCItem(id: "java-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "kotlin":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || t.hasPrefix("object ") || t.hasPrefix("fun ") {
                    return TOCItem(id: "kotlin-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "go":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("func ") || t.hasPrefix("type ") {
                    return TOCItem(id: "go-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "ruby":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("def ") || t.hasPrefix("class ") || t.hasPrefix("module ") {
                    return TOCItem(id: "ruby-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "rust":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("fn ") || t.hasPrefix("struct ") || t.hasPrefix("enum ") || t.hasPrefix("impl ") {
                    return TOCItem(id: "rust-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "typescript":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("function ") || t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("type ") {
                    return TOCItem(id: "ts-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "php":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("function ") || t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("trait ") {
                    return TOCItem(id: "php-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "objective-c":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("@interface") || t.hasPrefix("@implementation") || t.contains(")\n{") {
                    return TOCItem(id: "objc-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "c", "cpp":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("(") && !trimmed.contains(";") && (trimmed.hasPrefix("void ") || trimmed.hasPrefix("int ") || trimmed.hasPrefix("float ") || trimmed.hasPrefix("double ") || trimmed.hasPrefix("char ") || trimmed.contains("{")) {
                    return TOCItem(id: "c-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "bash", "zsh":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Simple function detection: name() { or function name { or name()\n{
                if trimmed.range(of: "^([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\)\\s*\\{", options: .regularExpression) != nil ||
                   trimmed.range(of: "^function\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\{", options: .regularExpression) != nil {
                    return TOCItem(id: "sh-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "powershell":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.range(of: #"^function\s+[A-Za-z_][A-Za-z0-9_\-]*\s*\{"#, options: .regularExpression) != nil ||
                   trimmed.hasPrefix("param(") {
                    return TOCItem(id: "ps-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "html", "css", "json", "markdown", "csv":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && (trimmed.hasPrefix("#") || trimmed.hasPrefix("<h")) {
                    return TOCItem(id: "markup-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "csharp":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("enum ") || t.contains(" static void Main(") || (t.contains(" void ") && t.contains("(") && t.contains(")") && t.contains("{")) {
                    return TOCItem(id: "cs-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        default:
            // For unknown or standard/plain, show first non-empty lines as headings
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && t.count < 120 {
                    return TOCItem(id: "default-\(index)", title: "\(t) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        }

        return toc.isEmpty
            ? [TOCItem(id: "none", title: "No headers found", line: nil)]
            : toc
    }
}
struct ProjectStructureSidebarView: View {
    private enum SidebarDensity: String, CaseIterable, Identifiable {
        case compact
        case comfortable

        var id: String { rawValue }
    }

    private struct FileIconStyle {
        let symbol: String
        let color: Color
    }

    let rootFolderURL: URL?
    let nodes: [ProjectTreeNode]
    let selectedFileURL: URL?
    let showSupportedFilesOnly: Bool
    let translucentBackgroundEnabled: Bool
    let boundaryEdge: HorizontalEdge?
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onToggleSupportedFilesOnly: (Bool) -> Void
    let onOpenProjectFile: (URL) -> Void
    let onRefreshTree: () -> Void
    @State private var expandedDirectories: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif
    @AppStorage("SettingsProjectSidebarDensity") private var sidebarDensityRaw: String = SidebarDensity.compact.rawValue
    @AppStorage("SettingsProjectSidebarAutoCollapseDeep") private var autoCollapseDeepFolders: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsInlineSidebarHeader {
                HStack {
                    Text("Project Structure")
                        .font(.system(size: isCompactDensity ? 19 : 20, weight: .semibold))
                    Spacer()
                    Button(action: onOpenFolder) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Open Folder…")

                    Button(action: onOpenFile) {
                        Image(systemName: "doc.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .help("Open File…")

                    Button(action: onRefreshTree) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh Folder Tree")

                    Menu {
                        Button {
                            onToggleSupportedFilesOnly(!showSupportedFilesOnly)
                        } label: {
                            Label(
                                "Show Supported Files Only",
                                systemImage: showSupportedFilesOnly ? "checkmark.circle.fill" : "circle"
                            )
                        }
                        Divider()
                        Picker("Density", selection: $sidebarDensityRaw) {
                            Text("Compact").tag(SidebarDensity.compact.rawValue)
                            Text("Comfortable").tag(SidebarDensity.comfortable.rawValue)
                        }
                        Toggle("Auto-collapse Deep Folders", isOn: $autoCollapseDeepFolders)
                        Divider()
                        Button("Expand All") {
                            expandAllDirectories()
                        }
                        Button("Collapse All") {
                            collapseAllDirectories()
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Expand or Collapse All")
                    .accessibilityLabel("Expand or collapse all folders")
                    .accessibilityHint("Expands or collapses all folders in the project tree")
                }
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.top, headerTopPadding)
                .padding(.bottom, headerBottomPadding)
#if os(macOS)
                .background(sidebarHeaderFill)
#endif
            }

            if let rootFolderURL {
                Text(rootFolderURL.path)
                    .font(.system(size: isCompactDensity ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(isCompactDensity ? 1 : 2)
                    .textSelection(.enabled)
                    .padding(.horizontal, headerHorizontalPadding)
                    .padding(.top, showsInlineSidebarHeader ? 0 : headerTopPadding)
                    .padding(.bottom, headerPathBottomPadding)
            }

            List {
                if rootFolderURL == nil {
                    Text("No folder selected")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if nodes.isEmpty {
                    Text("Folder is empty")
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(nodes) { node in
                        projectNodeView(node, level: 0)
                    }
                }
            }
            .listStyle(platformListStyle)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .padding(sidebarOuterPadding)
        .background(sidebarContainerShape.fill(sidebarSurfaceFill))
        .overlay(sidebarContainerBorderOverlay)
        .clipShape(sidebarContainerShape)
#if os(macOS)
        .overlay(alignment: boundaryEdge == .leading ? .leading : .trailing) {
            if boundaryEdge != nil {
                Rectangle()
                    .fill(sidebarSeparatorColor)
                    .frame(width: 1)
            }
        }
#endif
    }

    private var sidebarSurfaceFill: AnyShapeStyle {
        if translucentBackgroundEnabled {
            #if os(macOS)
            let mode = MacTranslucencyMode(rawValue: macTranslucencyModeRaw) ?? .balanced
            return AnyShapeStyle(mode.material.opacity(mode.opacity))
            #else
            return AnyShapeStyle(.ultraThinMaterial)
            #endif
        }
#if os(macOS)
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
#else
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
#endif
    }

    private var sidebarSurfaceStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var sidebarHeaderFill: AnyShapeStyle {
        translucentBackgroundEnabled ? sidebarSurfaceFill : AnyShapeStyle(Color.clear)
    }

    private var sidebarSeparatorColor: Color {
#if os(macOS)
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10)
#else
        Color.black.opacity(0.1)
#endif
    }

    private var sidebarCornerRadius: CGFloat {
#if os(macOS)
        18
#else
        14
#endif
    }

    private var sidebarContainerShape: AnyShape {
#if os(macOS)
        AnyShape(Rectangle())
#elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            AnyShape(Rectangle())
        } else {
            AnyShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: sidebarCornerRadius,
                    bottomTrailingRadius: sidebarCornerRadius,
                    topTrailingRadius: 0,
                    style: .continuous
                )
            )
        }
#else
        AnyShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: sidebarCornerRadius,
                bottomTrailingRadius: sidebarCornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
#endif
    }

    @ViewBuilder
    private var sidebarContainerBorderOverlay: some View {
#if os(macOS)
        EmptyView()
#elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom != .pad {
            sidebarContainerShape.stroke(sidebarSurfaceStroke, lineWidth: 1)
        }
#else
        sidebarContainerShape.stroke(sidebarSurfaceStroke, lineWidth: 1)
#endif
    }

    private var sidebarOuterPadding: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 0 : 10
#else
        0
#endif
    }

    private var platformListStyle: some ListStyle {
#if os(iOS)
        PlainListStyle()
#else
        PlainListStyle()
#endif
    }

    private func expandAllDirectories() {
        expandedDirectories = allDirectoryNodeIDs(in: nodes, level: 0)
    }

    private func collapseAllDirectories() {
        expandedDirectories.removeAll()
    }

    private func allDirectoryNodeIDs(in treeNodes: [ProjectTreeNode], level: Int) -> Set<String> {
        var result: Set<String> = []
        for node in treeNodes where node.isDirectory {
            let shouldInclude = !autoCollapseDeepFolders || level < 2
            if shouldInclude {
                result.insert(node.id)
            }
            result.formUnion(allDirectoryNodeIDs(in: node.children, level: level + 1))
        }
        return result
    }

    private func projectNodeView(_ node: ProjectTreeNode, level: Int) -> AnyView {
        if node.isDirectory {
            return AnyView(
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedDirectories.contains(node.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedDirectories.insert(node.id)
                        } else {
                            expandedDirectories.remove(node.id)
                        }
                    }
                )) {
                    ForEach(node.children) { child in
                        projectNodeView(child, level: level + 1)
                    }
                } label: {
                    HStack(spacing: directoryRowContentSpacing) {
                        Image(systemName: "folder")
                            .foregroundStyle(Color.accentColor)
                            .symbolRenderingMode(.hierarchical)
                        Text(node.url.lastPathComponent)
                            .lineLimit(1)
                    }
                    .font(rowFont)
                    .padding(.vertical, rowVerticalPadding)
                    .padding(.trailing, rowHorizontalPadding)
                    .padding(.leading, directoryRowContentLeadingPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowChrome(isSelected: false))
                }
                .padding(.leading, directoryRowLeadingInset(for: level))
                .listRowInsets(rowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            )
        } else {
            let style = fileIconStyle(for: node.url)
            let isSelected = selectedFileURL?.standardizedFileURL == node.url.standardizedFileURL
            return AnyView(
                Button {
                    onOpenProjectFile(node.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: style.symbol)
                            .foregroundStyle(style.color)
                            .symbolRenderingMode(.hierarchical)
                        Text(node.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        if isSelected {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundColor(.white.opacity(colorScheme == .dark ? 0.92 : 0.98))
                        }
                    }
                    .font(rowFont)
                    .foregroundStyle(isSelected ? rowSelectedForegroundColor : Color.primary)
                    .padding(.vertical, rowVerticalPadding)
                    .padding(.horizontal, rowHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowChrome(isSelected: isSelected))
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(level) * levelIndent)
                .listRowInsets(rowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            )
        }
    }

    private var sidebarDensity: SidebarDensity {
        SidebarDensity(rawValue: sidebarDensityRaw) ?? .compact
    }

    private var isCompactDensity: Bool { sidebarDensity == .compact }

    private var levelIndent: CGFloat {
        isCompactDensity ? 8 : 11
    }

    private var rowVerticalPadding: CGFloat {
        isCompactDensity ? 6 : 8
    }

    private var rowHorizontalPadding: CGFloat {
        isCompactDensity ? 10 : 12
    }

    private var directoryRowContentSpacing: CGFloat {
#if os(macOS)
        isCompactDensity ? 4 : 5
#else
        isCompactDensity ? 6 : 7
#endif
    }

    private var directoryRowContentLeadingPadding: CGFloat {
#if os(macOS)
        isCompactDensity ? 0 : 1
#else
        isCompactDensity ? 3 : 4
#endif
    }

    private var headerHorizontalPadding: CGFloat {
        isCompactDensity ? 16 : 18
    }

    private var headerTopPadding: CGFloat {
        isCompactDensity ? 16 : 18
    }

    private var headerBottomPadding: CGFloat {
        isCompactDensity ? 10 : 12
    }

    private var headerPathBottomPadding: CGFloat {
        isCompactDensity ? 10 : 12
    }

    private var rowInsets: EdgeInsets {
        EdgeInsets(top: 2, leading: isCompactDensity ? 8 : 10, bottom: 2, trailing: isCompactDensity ? 8 : 10)
    }

    private var showsInlineSidebarHeader: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
#else
        true
#endif
    }

    private func directoryRowLeadingInset(for level: Int) -> CGFloat {
        let baseInset: CGFloat
#if os(macOS)
        baseInset = level == 0 ? (isCompactDensity ? 6 : 8) : 0
#else
        baseInset = level == 0 ? (isCompactDensity ? 4 : 6) : 0
#endif
        return baseInset + CGFloat(level) * levelIndent
    }

    private var rowFont: Font {
        .system(size: isCompactDensity ? 13 : 14, weight: .medium)
    }

    private var rowSelectedForegroundColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private func rowChrome(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: isCompactDensity ? 12 : 14, style: .continuous)
            .fill(isSelected ? selectedRowFill : unselectedRowFill)
    }

    private var selectedRowFill: Color {
        if colorScheme == .dark {
            return Color.accentColor.opacity(0.42)
        }
        return Color.accentColor.opacity(0.18)
    }

    private var unselectedRowFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.018)
    }

    private func fileIconStyle(for url: URL) -> FileIconStyle {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        switch ext {
        case "swift":
            return .init(symbol: "swift", color: .orange)
        case "js", "mjs", "cjs":
            return .init(symbol: "curlybraces.square", color: .yellow)
        case "ts", "tsx":
            return .init(symbol: "chevron.left.forwardslash.chevron.right", color: .blue)
        case "json", "jsonc", "json5":
            return .init(symbol: "curlybraces", color: .green)
        case "md", "markdown":
            return .init(symbol: "text.alignleft", color: .teal)
        case "tex", "latex", "bib", "sty", "cls":
            return .init(symbol: "text.book.closed", color: .indigo)
        case "yml", "yaml", "toml", "ini", "env":
            return .init(symbol: "slider.horizontal.3", color: .mint)
        case "html", "htm":
            return .init(symbol: "chevron.left.slash.chevron.right", color: .orange)
        case "css":
            return .init(symbol: "paintbrush.pointed", color: .cyan)
        case "xml", "svg":
            return .init(symbol: "diamond", color: .pink)
        case "sh", "bash", "zsh", "ps1":
            return .init(symbol: "terminal", color: .indigo)
        case "py":
            return .init(symbol: "chevron.left.forwardslash.chevron.right", color: .yellow)
        case "rb":
            return .init(symbol: "diamond.fill", color: .red)
        case "go":
            return .init(symbol: "g.circle", color: .cyan)
        case "rs":
            return .init(symbol: "gearshape.2", color: .orange)
        case "sql":
            return .init(symbol: "cylinder", color: .purple)
        case "csv", "tsv":
            return .init(symbol: "tablecells", color: .green)
        case "txt", "log":
            return .init(symbol: "doc.plaintext", color: .secondary)
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return .init(symbol: "photo", color: .purple)
        case "pdf":
            return .init(symbol: "doc.richtext", color: .red)
        default:
            if name.hasPrefix(".git") {
                return .init(symbol: "arrow.triangle.branch", color: .orange)
            }
            if name.hasPrefix(".env") {
                return .init(symbol: "lock.doc", color: .mint)
            }
            return .init(symbol: "doc.text", color: .secondary)
        }
    }
}

struct ProjectTreeNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var children: [ProjectTreeNode]
    var id: String { url.path }
}

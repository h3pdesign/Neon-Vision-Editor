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

    private enum SidebarDisclosureSymbolStyle: String, CaseIterable, Identifiable {
        case chevron
        case triangle
        case caret
        case plusMinus

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chevron: return "Chevron"
            case .triangle: return "Triangle"
            case .caret: return "Caret"
            case .plusMinus: return "Plus/Minus"
            }
        }

        func symbolName(isExpanded: Bool) -> String {
            switch self {
            case .chevron:
                return isExpanded ? "chevron.down" : "chevron.forward"
            case .triangle:
                return isExpanded ? "arrowtriangle.down.fill" : "arrowtriangle.right.fill"
            case .caret:
                return isExpanded ? "chevron.compact.down" : "chevron.compact.right"
            case .plusMinus:
                return isExpanded ? "minus.square" : "plus.square"
            }
        }
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
    let onCreateProjectFile: (URL?) -> Void
    let onCreateProjectFolder: (URL?) -> Void
    let onRenameProjectItem: (URL) -> Void
    let onDuplicateProjectItem: (URL) -> Void
    let onDeleteProjectItem: (URL) -> Void
    let revealURL: URL?
    @State private var expandedDirectories: Set<String> = []
    @State private var hoveredNodeID: String? = nil
    @Environment(\.colorScheme) private var colorScheme
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif
    @AppStorage("SettingsProjectSidebarDensity") private var sidebarDensityRaw: String = SidebarDensity.compact.rawValue
    @AppStorage("SettingsProjectSidebarAutoCollapseDeep") private var autoCollapseDeepFolders: Bool = true
    @AppStorage("SettingsProjectSidebarDisclosureSymbolStyle") private var disclosureSymbolStyleRaw: String = SidebarDisclosureSymbolStyle.chevron.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSidebarActionsRow {
                VStack(alignment: .leading, spacing: isCompactDensity ? 8 : 10) {
                    if showsInlineSidebarTitle {
                        Text(NSLocalizedString("Project Structure", comment: "Project structure sidebar title"))
                            .font(.system(size: isCompactDensity ? 19 : 20, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                    }
                    HStack(spacing: isCompactDensity ? 10 : 12) {
                        Button(action: onOpenFolder) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Open Folder…", comment: "Project sidebar open folder action"))
                        .accessibilityLabel(NSLocalizedString("Open folder", comment: "Project sidebar open folder accessibility label"))
                        .accessibilityHint(NSLocalizedString("Select a project folder to show in the sidebar", comment: "Project sidebar open folder accessibility hint"))

                        Button(action: onOpenFile) {
                            Image(systemName: "doc")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Open File…", comment: "Project sidebar open file action"))
                        .accessibilityLabel(NSLocalizedString("Open file", comment: "Project sidebar open file accessibility label"))
                        .accessibilityHint(NSLocalizedString("Opens a file from disk", comment: "Project sidebar open file accessibility hint"))

                        Menu {
                            Button {
                                onCreateProjectFile(nil)
                            } label: {
                                Label(NSLocalizedString("New File", comment: "Project sidebar create file action"), systemImage: "doc.badge.plus")
                            }

                            Button {
                                onCreateProjectFolder(nil)
                            } label: {
                                Label(NSLocalizedString("New Folder", comment: "Project sidebar create folder action"), systemImage: "folder.badge.plus")
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Create in Project Root", comment: "Project sidebar create action"))
                        .accessibilityLabel(NSLocalizedString("Create project item", comment: "Project sidebar create accessibility label"))
                        .accessibilityHint(NSLocalizedString("Creates a new file or folder in the project root", comment: "Project sidebar create accessibility hint"))

                        Button(action: onRefreshTree) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Refresh Folder Tree", comment: "Project sidebar refresh tree action"))
                        .accessibilityLabel(NSLocalizedString("Refresh project tree", comment: "Project sidebar refresh accessibility label"))
                        .accessibilityHint(NSLocalizedString("Reloads files and folders from disk", comment: "Project sidebar refresh accessibility hint"))

                        Menu {
                            Button {
                                onToggleSupportedFilesOnly(!showSupportedFilesOnly)
                            } label: {
                                Label(
                                    NSLocalizedString("Show Supported Files Only", comment: "Project sidebar supported files filter label"),
                                    systemImage: showSupportedFilesOnly ? "checkmark.circle.fill" : "circle"
                                )
                            }
                            Divider()
                            Picker(NSLocalizedString("Density", comment: "Project sidebar density picker label"), selection: $sidebarDensityRaw) {
                                Text(NSLocalizedString("Compact", comment: "Project sidebar compact density")).tag(SidebarDensity.compact.rawValue)
                                Text(NSLocalizedString("Comfortable", comment: "Project sidebar comfortable density")).tag(SidebarDensity.comfortable.rawValue)
                            }
                            Picker(NSLocalizedString("Disclosure Icon", comment: "Project sidebar disclosure icon style picker label"), selection: $disclosureSymbolStyleRaw) {
                                ForEach(SidebarDisclosureSymbolStyle.allCases) { style in
                                    Text(style.title).tag(style.rawValue)
                                }
                            }
                            Toggle(NSLocalizedString("Auto-collapse Deep Folders", comment: "Project sidebar auto-collapse deep folders toggle"), isOn: $autoCollapseDeepFolders)
                            Divider()
                            Button(NSLocalizedString("Expand All", comment: "Project sidebar expand all action")) {
                                expandAllDirectories()
                            }
                            Button(NSLocalizedString("Collapse All", comment: "Project sidebar collapse all action")) {
                                collapseAllDirectories()
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Expand or Collapse All", comment: "Project sidebar expand/collapse help"))
                        .accessibilityLabel(NSLocalizedString("Expand or collapse all folders", comment: "Project sidebar expand/collapse accessibility label"))
                        .accessibilityHint(NSLocalizedString("Expands or collapses all folders in the project tree", comment: "Project sidebar expand/collapse accessibility hint"))

                        Spacer(minLength: 0)
                    }
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
                    .contextMenu {
                        Button {
                            onCreateProjectFile(rootFolderURL)
                        } label: {
                            Label(NSLocalizedString("New File", comment: "Project sidebar create file action"), systemImage: "doc.badge.plus")
                        }
                        Button {
                            onCreateProjectFolder(rootFolderURL)
                        } label: {
                            Label(NSLocalizedString("New Folder", comment: "Project sidebar create folder action"), systemImage: "folder.badge.plus")
                        }
                    }
                    .padding(.horizontal, headerHorizontalPadding)
                    .padding(.top, showsSidebarActionsRow ? 0 : headerTopPadding)
                    .padding(.bottom, headerPathBottomPadding)
            }

            List {
                if rootFolderURL == nil {
                    Text(NSLocalizedString("No folder selected", comment: "Project sidebar empty state without root folder"))
                        .foregroundColor(.secondary)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else if nodes.isEmpty {
                    Text(NSLocalizedString("Folder is empty", comment: "Project sidebar empty state for selected folder"))
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
            .contextMenu {
                if let rootFolderURL {
                    Button {
                        onCreateProjectFile(rootFolderURL)
                    } label: {
                        Label(NSLocalizedString("New File", comment: "Project sidebar create file action"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        onCreateProjectFolder(rootFolderURL)
                    } label: {
                        Label(NSLocalizedString("New Folder", comment: "Project sidebar create folder action"), systemImage: "folder.badge.plus")
                    }
                }
            }
        }
        .padding(sidebarOuterPadding)
        .background(sidebarContainerShape.fill(sidebarSurfaceFill))
        .overlay(sidebarContainerBorderOverlay)
        .clipShape(sidebarContainerShape)
        .onAppear {
            revealTargetIfNeeded()
        }
        .onChange(of: revealPath) { _, _ in
            revealTargetIfNeeded()
        }
        .onChange(of: nodes.count) { _, _ in
            revealTargetIfNeeded()
        }
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
            let isHovered = hoveredNodeID == node.id
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
                            .foregroundStyle(folderIconColor(isHovered: isHovered))
                            .symbolRenderingMode(.hierarchical)
                        Text(node.url.lastPathComponent)
                            .lineLimit(1)
                    }
                    .font(rowFont)
                    .padding(.vertical, directoryRowVerticalPadding)
                    .padding(.trailing, rowHorizontalPadding)
                    .padding(.leading, directoryRowContentLeadingPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowChrome(isSelected: false, isHovered: isHovered))
                    .contentShape(Rectangle())
                    .opacity(directoryRowVisualOpacity(nodeID: node.id, isHovered: isHovered))
                    .animation(.easeOut(duration: 0.14), value: isHovered)
                    .animation(.easeOut(duration: 0.14), value: expandedDirectories.contains(node.id))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        Text(
                            String(
                                format: NSLocalizedString("Folder %@", comment: "Project sidebar folder accessibility label"),
                                node.url.lastPathComponent
                            )
                        )
                    )
                    .accessibilityHint(
                        Text(
                            NSLocalizedString(
                                "Expands or collapses this folder without changing the selected file.",
                                comment: "Project sidebar folder disclosure accessibility hint"
                            )
                        )
                    )
                }
                .padding(.leading, directoryRowLeadingInset(for: level))
                .padding(.vertical, rowOuterSpacing(for: level, isDirectory: true))
                .listRowInsets(directoryRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .disclosureGroupStyle(projectDisclosureStyle)
                .contextMenu {
                    Button {
                        onCreateProjectFile(node.url)
                    } label: {
                        Label(NSLocalizedString("New File", comment: "Project sidebar create file action"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        onCreateProjectFolder(node.url)
                    } label: {
                        Label(NSLocalizedString("New Folder", comment: "Project sidebar create folder action"), systemImage: "folder.badge.plus")
                    }
                    Divider()
                    Button {
                        onRenameProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Rename", comment: "Project sidebar rename action"), systemImage: "pencil")
                    }
                    Button {
                        onDuplicateProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Duplicate", comment: "Project sidebar duplicate action"), systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeleteProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Delete", comment: "Project sidebar delete action"), systemImage: "trash")
                    }
                }
#if os(macOS)
                .onHover { hovering in
                    if hovering {
                        hoveredNodeID = node.id
                    } else if hoveredNodeID == node.id {
                        hoveredNodeID = nil
                    }
                }
#endif
            )
        } else {
            let style = fileIconStyle(for: node.url)
            let isSelected = selectedFileURL?.standardizedFileURL == node.url.standardizedFileURL
            let isHovered = hoveredNodeID == node.id
            return AnyView(
                Button {
                    onOpenProjectFile(node.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: style.symbol)
                            .foregroundStyle(fileIconColor(style: style, isSelected: isSelected, isHovered: isHovered))
                            .symbolRenderingMode(.hierarchical)
                        Text(node.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(rowFont)
                    .foregroundStyle(isSelected ? rowSelectedForegroundColor : Color.primary)
                    .padding(.vertical, rowVerticalPadding)
                    .padding(.horizontal, rowHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(rowChrome(isSelected: isSelected, isHovered: isHovered))
                    .contentShape(Rectangle())
                    .animation(.easeOut(duration: 0.14), value: isHovered)
                    .animation(.easeOut(duration: 0.14), value: isSelected)
                }
                .buttonStyle(.plain)
                .padding(.leading, fileRowLeadingInset(for: level))
                .padding(.vertical, rowOuterSpacing(for: level, isDirectory: false))
                .listRowInsets(rowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contextMenu {
                    Button {
                        onCreateProjectFile(node.url.deletingLastPathComponent())
                    } label: {
                        Label(NSLocalizedString("New File Here", comment: "Project sidebar create file in same directory action"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        onCreateProjectFolder(node.url.deletingLastPathComponent())
                    } label: {
                        Label(NSLocalizedString("New Folder Here", comment: "Project sidebar create folder in same directory action"), systemImage: "folder.badge.plus")
                    }
                    Divider()
                    Button {
                        onRenameProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Rename", comment: "Project sidebar rename action"), systemImage: "pencil")
                    }
                    Button {
                        onDuplicateProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Duplicate", comment: "Project sidebar duplicate action"), systemImage: "plus.square.on.square")
                    }
                    Divider()
                    Button(role: .destructive) {
                        onDeleteProjectItem(node.url)
                    } label: {
                        Label(NSLocalizedString("Delete", comment: "Project sidebar delete action"), systemImage: "trash")
                    }
                }
                .accessibilityLabel(
                    Text(
                        String(
                            format: NSLocalizedString("File %@", comment: "Project sidebar file accessibility label"),
                            node.url.lastPathComponent
                        )
                    )
                )
#if os(macOS)
                .onHover { hovering in
                    if hovering {
                        hoveredNodeID = node.id
                    } else if hoveredNodeID == node.id {
                        hoveredNodeID = nil
                    }
                }
#endif
            )
        }
    }

    private var sidebarDensity: SidebarDensity {
        SidebarDensity(rawValue: sidebarDensityRaw) ?? .compact
    }

    private var disclosureSymbolStyle: SidebarDisclosureSymbolStyle {
        SidebarDisclosureSymbolStyle(rawValue: disclosureSymbolStyleRaw) ?? .chevron
    }

    private var isCompactDensity: Bool { sidebarDensity == .compact }

    private var levelIndent: CGFloat {
        isCompactDensity ? 9 : 13
    }

    private var rowVerticalPadding: CGFloat {
        isCompactDensity ? 6 : 10
    }

    private var directoryRowVerticalPadding: CGFloat {
        rowVerticalPadding + (isCompactDensity ? 1 : 2)
    }

    private var rowHorizontalPadding: CGFloat {
        isCompactDensity ? 10 : 14
    }

    private var directoryRowContentSpacing: CGFloat {
#if os(macOS)
        isCompactDensity ? 3 : 4
#else
        isCompactDensity ? 6 : 7
#endif
    }

    private var directoryRowContentLeadingPadding: CGFloat {
#if os(macOS)
        0
#else
        isCompactDensity ? 4 : 5
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
        directoryRowInsets
    }

    private var directoryRowInsets: EdgeInsets {
        let macLeadingInset: CGFloat = {
#if os(macOS)
            let base: CGFloat = isCompactDensity ? 28 : 32
            return translucentBackgroundEnabled ? base + 2 : base
#else
            return isCompactDensity ? 24 : 28
#endif
        }()
        return EdgeInsets(top: 2, leading: macLeadingInset, bottom: 2, trailing: isCompactDensity ? 10 : 12)
    }

    private var showsInlineSidebarTitle: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom != .phone
#else
        true
#endif
    }

    private var showsSidebarActionsRow: Bool {
        true
    }

    private func directoryRowLeadingInset(for level: Int) -> CGFloat {
        let baseInset: CGFloat
#if os(macOS)
        baseInset = level == 0 ? 0 : 5
#else
        baseInset = level == 0 ? (isCompactDensity ? 18 : 20) : 8
#endif
        return baseInset + CGFloat(level) * levelIndent
    }

    private func fileRowLeadingInset(for level: Int) -> CGFloat {
        directoryRowLeadingInset(for: level)
            + disclosureIconColumnWidth
            + disclosureIconToLabelSpacing
            - rowHorizontalPadding
    }

    private var rowFont: Font {
        .system(size: isCompactDensity ? 13 : 14, weight: .medium)
    }

    private var rowSelectedForegroundColor: Color {
        colorScheme == .dark ? .white : .primary
    }

    private func rowChrome(isSelected: Bool, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: isCompactDensity ? 10 : 12, style: .continuous)
            .fill(rowFill(isSelected: isSelected, isHovered: isHovered))
    }

    private func rowFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return selectedRowFill }
        if isHovered { return hoveredRowFill }
        return unselectedRowFill
    }

    private var selectedRowFill: Color {
        if translucentBackgroundEnabled {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.34 : 0.20)
        }
        if colorScheme == .dark { return Color.accentColor.opacity(0.42) }
        return Color.accentColor.opacity(0.20)
    }

    private var hoveredRowFill: Color {
        if translucentBackgroundEnabled {
            return colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
        }
        if colorScheme == .dark { return Color.white.opacity(0.07) }
        return Color.black.opacity(0.055)
    }

    private var unselectedRowFill: Color {
        if translucentBackgroundEnabled {
            return colorScheme == .dark ? Color.white.opacity(0.036) : Color.black.opacity(0.022)
        }
        return colorScheme == .dark ? Color.white.opacity(0.024) : Color.black.opacity(0.018)
    }

    private func rowOuterSpacing(for level: Int, isDirectory: Bool) -> CGFloat {
        if level == 0 {
            return isCompactDensity ? 1 : 2
        }
        if isDirectory {
            return 0
        }
        return isCompactDensity ? 0.5 : 1
    }

    private func folderIconColor(isHovered: Bool) -> Color {
        if isHovered {
            return Color.accentColor
        }
        return translucentBackgroundEnabled ? Color.accentColor.opacity(0.92) : Color.accentColor.opacity(0.96)
    }

    private func fileIconColor(style: FileIconStyle, isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected || isHovered {
            return style.color
        }
        return style.color.opacity(translucentBackgroundEnabled ? 0.68 : 0.74)
    }

    private func directoryRowVisualOpacity(nodeID: String, isHovered: Bool) -> Double {
        if isHovered || expandedDirectories.contains(nodeID) { return 1.0 }
        return translucentBackgroundEnabled ? 0.96 : 0.94
    }

    private var projectDisclosureStyle: SidebarDisclosureStyle {
        SidebarDisclosureStyle(
            symbolName: { isExpanded in disclosureSymbolStyle.symbolName(isExpanded: isExpanded) },
            iconColor: disclosureIconColor,
            iconSize: disclosureIconSize,
            iconToLabelSpacing: disclosureIconToLabelSpacing,
            iconColumnWidth: disclosureIconColumnWidth
        )
    }

    private var disclosureIconColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.74)
    }

    private var disclosureIconSize: CGFloat {
        isCompactDensity ? 11 : 12
    }

    private var disclosureIconToLabelSpacing: CGFloat {
        isCompactDensity ? 2 : 3
    }

    private var disclosureIconColumnWidth: CGFloat {
#if os(macOS)
        isCompactDensity ? 20 : 22
#else
        isCompactDensity ? 18 : 20
#endif
    }

    private var revealPath: String? {
        revealURL?.standardizedFileURL.path
    }

    private func revealTargetIfNeeded() {
        guard let revealPath else { return }
        guard let pathIDs = directoryPathIDs(for: revealPath, in: nodes) else { return }
        expandedDirectories.formUnion(pathIDs)
    }

    private func directoryPathIDs(for targetPath: String, in treeNodes: [ProjectTreeNode]) -> [String]? {
        for node in treeNodes {
            if let path = directoryPathIDs(for: targetPath, node: node) {
                return path
            }
        }
        return nil
    }

    private func directoryPathIDs(for targetPath: String, node: ProjectTreeNode) -> [String]? {
        let nodePath = node.url.standardizedFileURL.path
        if nodePath == targetPath {
            return node.isDirectory ? [node.id] : []
        }
        guard node.isDirectory else { return nil }
        for child in node.children {
            if let childPath = directoryPathIDs(for: targetPath, node: child) {
                return [node.id] + childPath
            }
        }
        return nil
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
        case "cif", "mcif":
            return .init(symbol: "atom", color: .blue)
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

private struct SidebarDisclosureStyle: DisclosureGroupStyle {
    let symbolName: (Bool) -> String
    let iconColor: Color
    let iconSize: CGFloat
    let iconToLabelSpacing: CGFloat
    let iconColumnWidth: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: iconToLabelSpacing) {
                    Image(systemName: symbolName(configuration.isExpanded))
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: iconColumnWidth, alignment: .center)
                        .accessibilityHidden(true)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

struct ProjectTreeNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var children: [ProjectTreeNode]
    var id: String { url.path }
}

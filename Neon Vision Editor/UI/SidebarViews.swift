import SwiftUI
import Foundation

#if os(macOS)
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
        return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
#else
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.13, blue: 0.17),
                        Color(red: 0.15, green: 0.18, blue: 0.23)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.96, blue: 1.0),
                    Color(red: 0.88, green: 0.93, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
    let rootFolderURL: URL?
    let nodes: [ProjectTreeNode]
    let selectedFileURL: URL?
    let translucentBackgroundEnabled: Bool
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenProjectFile: (URL) -> Void
    let onRefreshTree: () -> Void
    @State private var expandedDirectories: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Project Structure")
                    .font(.headline)
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
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)
#if os(macOS)
            .background(sidebarHeaderFill)
#endif

            if let rootFolderURL {
                Text(rootFolderURL.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
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
        .background(
            RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                .fill(sidebarSurfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                        .stroke(sidebarSurfaceStroke, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
#if os(macOS)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(sidebarSurfaceFill)
                .frame(width: 2)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(sidebarSeparatorColor)
                .frame(width: 1)
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
        return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
#else
        if colorScheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.13, blue: 0.17),
                        Color(red: 0.15, green: 0.18, blue: 0.23)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    Color(red: 0.92, green: 0.96, blue: 1.0),
                    Color(red: 0.88, green: 0.93, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
        Color(nsColor: .separatorColor).opacity(0.7)
#else
        Color.black.opacity(0.1)
#endif
    }

    private var sidebarCornerRadius: CGFloat {
#if os(macOS)
        0
#else
        14
#endif
    }

    private var sidebarOuterPadding: CGFloat {
#if os(iOS)
        10
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
                    Label(node.url.lastPathComponent, systemImage: "folder")
                        .lineLimit(1)
                }
                .padding(.leading, CGFloat(level) * 10)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            )
        } else {
            return AnyView(
                Button {
                    onOpenProjectFile(node.url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text(node.url.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        if selectedFileURL?.standardizedFileURL == node.url.standardizedFileURL {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, CGFloat(level) * 10)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            )
        }
    }
}

struct ProjectTreeNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var children: [ProjectTreeNode]
    var id: String { url.path }
}

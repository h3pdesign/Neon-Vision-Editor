import SwiftUI
import Foundation

struct SidebarView: View {
    let content: String
    let language: String
    var body: some View {
        List {
            ForEach(generateTableOfContents(), id: \.self) { item in
                Button {
                    jump(to: item)
                } label: {
                    Text(item)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func jump(to item: String) {
        // Expect item format: "... (Line N)"
        if let startRange = item.range(of: "(Line "),
           let endRange = item.range(of: ")", range: startRange.upperBound..<item.endIndex) {
            let numberStr = item[startRange.upperBound..<endRange.lowerBound]
            if let lineOneBased = Int(numberStr.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)),
               lineOneBased > 0 {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .moveCursorToLine, object: lineOneBased)
                }
            }
        }
    }

    // Naive line-scanning TOC: looks for language-specific declarations or headers.
    func generateTableOfContents() -> [String] {
        guard !content.isEmpty else { return ["No content available"] }
        if (content as NSString).length >= 400_000 {
            return ["Large file detected: TOC disabled for performance"]
        }
        let lines = content.components(separatedBy: .newlines)
        var toc: [String] = []

        switch language {
        case "swift":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") ||
                   trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "python":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "javascript":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "java":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || (t.contains(" void ") || (t.contains(" public ") && t.contains("(") && t.contains(")"))) {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "kotlin":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || t.hasPrefix("object ") || t.hasPrefix("fun ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "go":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("func ") || t.hasPrefix("type ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "ruby":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("def ") || t.hasPrefix("class ") || t.hasPrefix("module ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "rust":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("fn ") || t.hasPrefix("struct ") || t.hasPrefix("enum ") || t.hasPrefix("impl ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "typescript":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("function ") || t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("type ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "php":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("function ") || t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("trait ") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "objective-c":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("@interface") || t.hasPrefix("@implementation") || t.contains(")\n{") {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        case "c", "cpp":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("(") && !trimmed.contains(";") && (trimmed.hasPrefix("void ") || trimmed.hasPrefix("int ") || trimmed.hasPrefix("float ") || trimmed.hasPrefix("double ") || trimmed.hasPrefix("char ") || trimmed.contains("{")) {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "bash", "zsh":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Simple function detection: name() { or function name { or name()\n{
                if trimmed.range(of: "^([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\)\\s*\\{", options: .regularExpression) != nil ||
                   trimmed.range(of: "^function\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\{", options: .regularExpression) != nil {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "powershell":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.range(of: #"^function\s+[A-Za-z_][A-Za-z0-9_\-]*\s*\{"#, options: .regularExpression) != nil ||
                   trimmed.hasPrefix("param(") {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "html", "css", "json", "markdown", "csv":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && (trimmed.hasPrefix("#") || trimmed.hasPrefix("<h")) {
                    return "\(trimmed) (Line \(index + 1))"
                }
                return nil
            }
        case "csharp":
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("class ") || t.hasPrefix("interface ") || t.hasPrefix("enum ") || t.contains(" static void Main(") || (t.contains(" void ") && t.contains("(") && t.contains(")") && t.contains("{")) {
                    return "\(t) (Line \(index + 1))"
                }
                return nil
            }
        default:
            // For unknown or standard/plain, show first non-empty lines as headings
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && t.count < 120 { return "\(t) (Line \(index + 1))" }
                return nil
            }
        }

        return toc.isEmpty ? ["No headers found"] : toc
    }
}
struct ProjectStructureSidebarView: View {
    let rootFolderURL: URL?
    @Binding var nodes: [ProjectTreeNode]
    let selectedFileURL: URL?
    let translucentBackgroundEnabled: Bool
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenProjectFile: (URL) -> Void
    let onRefreshTree: () -> Void
    let onLoadChildren: (URL) -> [ProjectTreeNode]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("SettingsLiquidGlassEnabled") private var liquidGlassEnabled: Bool = true
    @State private var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var expandedDirectories: Set<String> = []

    private var shouldUseSidebarGlass: Bool {
#if os(iOS)
        translucentBackgroundEnabled && liquidGlassEnabled && !reduceTransparency && !isLowPowerModeEnabled
#else
        translucentBackgroundEnabled && liquidGlassEnabled && !reduceTransparency
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                } else if nodes.isEmpty {
                    Text("Folder is empty")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(nodes) { node in
                        projectNodeView(node, level: 0)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(shouldUseSidebarGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
        }
        .background(shouldUseSidebarGlass ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.clear))
#if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
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
                            if !node.isChildrenLoaded {
                                let children = onLoadChildren(node.url)
                                updateChildren(for: node.id, children: children)
                            }
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
            )
        }
    }

    private func updateChildren(for nodeID: String, children: [ProjectTreeNode]) {
        func patch(nodes: inout [ProjectTreeNode]) -> Bool {
            for idx in nodes.indices {
                if nodes[idx].id == nodeID {
                    nodes[idx].children = children
                    nodes[idx].isChildrenLoaded = true
                    return true
                }
                if patch(nodes: &nodes[idx].children) {
                    return true
                }
            }
            return false
        }
        _ = patch(nodes: &nodes)
    }
}

struct ProjectTreeNode: Identifiable {
    let url: URL
    let isDirectory: Bool
    var children: [ProjectTreeNode]
    var isChildrenLoaded: Bool
    var id: String { url.path }
}

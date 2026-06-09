import SwiftUI
import Foundation

#if os(macOS)


// MARK: - macOS Sidebar Materials

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

// MARK: - Sidebar Table of Contents

struct SidebarView: View {
    private enum TOCItemKind: String, Hashable {
        case heading
        case type
        case function
        case property
        case comment
        case content
        case placeholder
    }

    private struct TOCItem: Identifiable, Hashable {
        let id: String
        let title: String
        let line: Int?
        let level: Int
        let kind: TOCItemKind
    }

    let content: String
    let language: String
    let contentUTF16Length: Int?
    let translucentBackgroundEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif
    @State private var tocItems: [TOCItem] = [
        TOCItem(id: "empty", title: "No content available", line: nil, level: 1, kind: .placeholder)
    ]
    @State private var tocRefreshTask: Task<Void, Never>?
    @State private var selectedTOCItemID: String?

    var body: some View {
        List {
            ForEach(tocItems) { item in
                Button {
                    selectedTOCItemID = item.id
                    jump(to: item)
                } label: {
                    tocRow(for: item)
                }
                .buttonStyle(.plain)
                .disabled(item.line == nil)
                .listRowInsets(tocListRowInsets)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityLabel(accessibilityLabel(for: item))
                .accessibilityAddTraits(selectedTOCItemID == item.id ? [.isSelected] : [])
            }
        }
        .listStyle(platformListStyle)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                .fill(sidebarSurfaceFill)
                .overlay(
                    RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
                        .stroke(sidebarSurfaceStroke, lineWidth: 1.2)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
        .padding(sidebarOuterPaddingInsets)
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
            ? Color.white.opacity(0.20)
            : Color.black.opacity(0.14)
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

    @ViewBuilder
    private func tocRow(for item: TOCItem) -> some View {
        let isSelected = selectedTOCItemID == item.id
        HStack(spacing: isCompactTOCWidth ? 6 : 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tocMarkerColor(for: item, isSelected: isSelected))
                .frame(width: isCompactTOCWidth ? 2.5 : 3, height: item.line == nil ? 16 : tocMarkerHeight)

            tocLeadingSymbol(for: item, isSelected: isSelected)

            Text(item.title)
                .font(tocTitleFont(for: item))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: isCompactTOCWidth ? 6 : 8)

            if let line = item.line {
                Text("L\(line)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.78))
            }
        }
        .padding(.leading, CGFloat(max(0, min(item.level, 6) - 1)) * tocIndentWidth)
        .padding(.vertical, tocRowVerticalPadding)
        .padding(.horizontal, tocRowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : sidebarRowFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func tocLeadingSymbol(for item: TOCItem, isSelected: Bool) -> some View {
        let color = isSelected ? Color.accentColor : tocMarkerColor(for: item, isSelected: false)
        if item.kind == .heading {
            Text(String(repeating: "#", count: max(1, min(item.level, 3))))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(width: 24, alignment: .leading)
        } else {
            Image(systemName: tocIconName(for: item.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 18)
        }
    }

    private func tocTitleFont(for item: TOCItem) -> Font {
        switch item.level {
        case 1:
            return .system(size: 13, weight: .semibold)
        case 2:
            return .system(size: 12.5, weight: .medium)
        default:
            return .system(size: 12, weight: .regular)
        }
    }

    private func tocMarkerColor(for item: TOCItem, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor
        }
        switch item.kind {
        case .heading:
            return Color.accentColor.opacity(0.70)
        case .type:
            return Color.purple.opacity(0.65)
        case .function:
            return Color.blue.opacity(0.62)
        case .property:
            return Color.orange.opacity(0.66)
        case .comment:
            return Color.green.opacity(0.60)
        case .content:
            return Color.secondary.opacity(0.45)
        case .placeholder:
            return Color.secondary.opacity(0.28)
        }
    }

    private func tocIconName(for kind: TOCItemKind) -> String {
        switch kind {
        case .heading:
            return "number"
        case .type:
            return "shippingbox"
        case .function:
            return "function"
        case .property:
            return "tag"
        case .comment:
            return "text.bubble"
        case .content:
            return "doc.text"
        case .placeholder:
            return "circle"
        }
    }

    private func accessibilityLabel(for item: TOCItem) -> String {
        if let line = item.line {
            return "\(item.title), line \(line)"
        }
        return item.title
    }

    private var tocListRowInsets: EdgeInsets {
#if os(iOS)
        let verticalInset: CGFloat = isCompactTOCWidth ? 0 : 1
        return EdgeInsets(
            top: verticalInset,
            leading: isCompactTOCWidth ? 6 : 0,
            bottom: verticalInset,
            trailing: isCompactTOCWidth ? 6 : 0
        )
#else
        return EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0)
#endif
    }

    private var tocRowVerticalPadding: CGFloat {
#if os(iOS)
        isCompactTOCWidth ? 5 : 6
#else
        8
#endif
    }

    private var tocRowHorizontalPadding: CGFloat {
#if os(iOS)
        isCompactTOCWidth ? 7 : 10
#else
        10
#endif
    }

    private var tocMarkerHeight: CGFloat {
#if os(iOS)
        isCompactTOCWidth ? 20 : 24
#else
        24
#endif
    }

    private var tocIndentWidth: CGFloat {
#if os(iOS)
        isCompactTOCWidth ? 9 : 12
#else
        12
#endif
    }

    private var isCompactTOCWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var sidebarOuterPaddingInsets: EdgeInsets {
#if os(iOS)
        EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10)
#else
        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 4)
#endif
    }

    private var sidebarCornerRadius: CGFloat {
#if os(macOS)
        22
#else
        20
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
        if let contentUTF16Length, contentUTF16Length >= Self.tocLargeContentUTF16Threshold {
            tocItems = [Self.placeholderTOCItem(id: "large", title: "Large file detected: TOC disabled for performance")]
            return
        }
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
            return [placeholderTOCItem(id: "empty", title: "No content available")]
        }
        if (content as NSString).length >= tocLargeContentUTF16Threshold {
            return [placeholderTOCItem(id: "large", title: "Large file detected: TOC disabled for performance")]
        }
        let lines = content.components(separatedBy: .newlines)
        var toc: [TOCItem] = []

        switch language {
        case "swift":
            toc = lines.enumerated().compactMap { index, line in
                swiftTOCItem(for: line, index: index, language: language)
            }
        case "python":
            toc = lines.enumerated().compactMap { index, line in
                pythonTOCItem(for: line, index: index, language: language)
            }
        case "javascript":
            toc = lines.enumerated().compactMap { index, line in
                scriptTOCItem(for: line, index: index, language: language, idPrefix: "js")
            }
        case "java":
            toc = lines.enumerated().compactMap { index, line in
                jvmTOCItem(for: line, index: index, language: language, idPrefix: "java")
            }
        case "kotlin":
            toc = lines.enumerated().compactMap { index, line in
                kotlinTOCItem(for: line, index: index, language: language)
            }
        case "go":
            toc = lines.enumerated().compactMap { index, line in
                goTOCItem(for: line, index: index, language: language)
            }
        case "ruby":
            toc = lines.enumerated().compactMap { index, line in
                rubyTOCItem(for: line, index: index, language: language)
            }
        case "rust":
            toc = lines.enumerated().compactMap { index, line in
                rustTOCItem(for: line, index: index, language: language)
            }
        case "typescript":
            toc = lines.enumerated().compactMap { index, line in
                scriptTOCItem(for: line, index: index, language: language, idPrefix: "ts")
            }
        case "php":
            toc = lines.enumerated().compactMap { index, line in
                phpTOCItem(for: line, index: index, language: language)
            }
        case "objective-c":
            toc = lines.enumerated().compactMap { index, line in
                objectiveCTOCItem(for: line, index: index, language: language)
            }
        case "c", "cpp":
            toc = lines.enumerated().compactMap { index, line in
                cFamilyTOCItem(for: line, index: index, language: language)
            }
        case "bash", "zsh":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Simple function detection: name() { or function name { or name()\n{
                if trimmed.range(of: "^([A-Za-z_][A-Za-z0-9_]*)\\s*\\(\\)\\s*\\{", options: .regularExpression) != nil ||
                   trimmed.range(of: "^function\\s+[A-Za-z_][A-Za-z0-9_]*\\s*\\{", options: .regularExpression) != nil {
                    return makeTOCItem(id: "sh-\(index)", title: trimmed, line: index + 1, language: language)
                }
                return nil
            }
        case "powershell":
            toc = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.range(of: #"^function\s+[A-Za-z_][A-Za-z0-9_\-]*\s*\{"#, options: .regularExpression) != nil ||
                   trimmed.hasPrefix("param(") {
                    return makeTOCItem(id: "ps-\(index)", title: trimmed, line: index + 1, language: language)
                }
                return nil
            }
        case "html", "css", "json", "markdown", "csv":
            toc = lines.enumerated().compactMap { index, line in
                markupTOCItem(for: line, previousLine: index > 0 ? lines[index - 1] : nil, index: index, language: language)
            }
        case "csharp":
            toc = lines.enumerated().compactMap { index, line in
                csharpTOCItem(for: line, index: index, language: language)
            }
        default:
            // For unknown or standard/plain, show first non-empty lines as headings
            toc = lines.enumerated().compactMap { index, line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty && t.count < 120 {
                    return makeTOCItem(id: "default-\(index)", title: t, line: index + 1, language: language)
                }
                return nil
            }
        }

        return toc.isEmpty
            ? [placeholderTOCItem(id: "none", title: "No headers found")]
            : toc
    }

    private static func swiftTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let leadingSpaces = line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { total, character in
            total + (character == "\t" ? 4 : 1)
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("//MARK:") {
            return makeTOCItem(id: "swift-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        guard leadingSpaces <= 8 else { return nil }

        let declarationPrefixes = [
            "struct ", "class ", "enum ", "actor ", "protocol ", "extension ",
            "func ", "var ", "let ", "typealias ", "init(", "deinit"
        ]
        if declarationPrefixes.contains(where: { trimmed.hasPrefix($0) }) {
            if swiftLineLooksLikeProperty(trimmed), leadingSpaces > 4 {
                return nil
            }
            return makeTOCItem(id: "swift-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if leadingSpaces <= 4,
           trimmed.hasPrefix("@"),
           trimmed.contains(" var ") || trimmed.contains(" let ") ||
           trimmed.contains(" func ") || trimmed.contains(" struct ") ||
           trimmed.contains(" class ") || trimmed.contains(" enum ") {
            return makeTOCItem(id: "swift-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let modifiers = [
            "private", "fileprivate", "internal", "public", "open",
            "static", "class", "final", "nonisolated", "override", "mutating",
            "nonmutating", "lazy", "weak", "unowned", "@MainActor"
        ]
        let words = trimmed.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        var tokenIndex = 0
        while tokenIndex < words.count {
            let token = words[tokenIndex].trimmingCharacters(in: CharacterSet(charactersIn: "(),"))
            if modifiers.contains(token) || token.hasPrefix("@") {
                tokenIndex += 1
            } else {
                break
            }
        }
        guard tokenIndex < words.count else { return nil }
        let declarationToken = words[tokenIndex].trimmingCharacters(in: CharacterSet(charactersIn: "(),"))
        if ["struct", "class", "enum", "actor", "protocol", "extension", "func", "var", "let", "typealias", "init", "deinit"].contains(declarationToken) {
            if ["var", "let"].contains(declarationToken), leadingSpaces > 4 {
                return nil
            }
            return makeTOCItem(id: "swift-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func pythonTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("# MARK:") || trimmed.hasPrefix("# region") {
            return makeTOCItem(id: "python-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if trimmed.range(of: #"^(async\s+)?def\s+[A-Za-z_][A-Za-z0-9_]*\s*\("#, options: .regularExpression) != nil ||
           trimmed.range(of: #"^class\s+[A-Za-z_][A-Za-z0-9_]*(\(|:)"#, options: .regularExpression) != nil {
            return makeTOCItem(id: "python-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func scriptTOCItem(for line: String, index: Int, language: String, idPrefix: String) -> TOCItem? {
        let leadingSpaces = leadingIndentSpaces(in: line)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "\(idPrefix)-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(export\s+default\s+|export\s+)?(abstract\s+)?class\s+[A-Za-z_$][A-Za-z0-9_$]*"#,
            #"^(export\s+)?(interface|type|enum|namespace)\s+[A-Za-z_$][A-Za-z0-9_$]*"#,
            #"^(export\s+)?(async\s+)?function\s+\*?\s*[A-Za-z_$][A-Za-z0-9_$]*\s*\("#,
            #"^(export\s+)?(const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*(async\s*)?(\([^=]*\)|[A-Za-z_$][A-Za-z0-9_$]*)\s*=>"#,
            #"^(export\s+)?(const|let|var)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*=\s*(async\s+)?function"#,
            #"^(public|private|protected|static|async|get|set)\s+.*\("#
        ]
        if leadingSpaces <= 8, patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "\(idPrefix)-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func jvmTOCItem(for line: String, index: Int, language: String, idPrefix: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "\(idPrefix)-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(public|protected|private|abstract|final|sealed|static|\s)*\s*(class|interface|enum|record)\s+[A-Za-z_][A-Za-z0-9_]*"#,
            #"^(public|protected|private|static|final|synchronized|native|abstract|\s)+[\w<>\[\], ?]+\s+[A-Za-z_][A-Za-z0-9_]*\s*\("#
        ]
        if patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "\(idPrefix)-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func kotlinTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "kotlin-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(public|private|protected|internal|data|sealed|open|abstract|enum|annotation|\s)*\s*(class|object|interface|enum class)\s+[A-Za-z_][A-Za-z0-9_]*"#,
            #"^(public|private|protected|internal|override|suspend|inline|operator|\s)*\s*fun\s+[\w.<>, ]+"#,
            #"^(public|private|protected|internal|override|lateinit|const|\s)*\s*(val|var)\s+[A-Za-z_][A-Za-z0-9_]*"#
        ]
        if leadingIndentSpaces(in: line) <= 8, patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "kotlin-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func goTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "go-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if trimmed.range(of: #"^func\s+(\([^)]+\)\s*)?[A-Za-z_][A-Za-z0-9_]*\s*\("#, options: .regularExpression) != nil ||
           trimmed.range(of: #"^type\s+[A-Za-z_][A-Za-z0-9_]*\s+(struct|interface|func|\w+)"#, options: .regularExpression) != nil ||
           trimmed.range(of: #"^(const|var)\s+(\(|[A-Za-z_][A-Za-z0-9_]*)"#, options: .regularExpression) != nil {
            return makeTOCItem(id: "go-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func rubyTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("# MARK:") || trimmed.hasPrefix("# region") {
            return makeTOCItem(id: "ruby-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if trimmed.range(of: #"^(def|class|module)\s+(self\.)?[A-Za-z_:][A-Za-z0-9_:!?=]*"#, options: .regularExpression) != nil {
            return makeTOCItem(id: "ruby-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func rustTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "rust-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(pub(\([^)]*\))?\s+)?(async\s+)?fn\s+[A-Za-z_][A-Za-z0-9_]*\s*\("#,
            #"^(pub(\([^)]*\))?\s+)?(struct|enum|trait|impl|type|mod)\s+"#
        ]
        if patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "rust-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func phpTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "php-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(abstract\s+|final\s+)?(class|interface|trait|enum)\s+[A-Za-z_][A-Za-z0-9_]*"#,
            #"^(public|protected|private|static|final|abstract|\s)*function\s+[A-Za-z_][A-Za-z0-9_]*\s*\("#
        ]
        if patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "php-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func objectiveCTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#pragma mark") || trimmed.hasPrefix("// MARK:") {
            return makeTOCItem(id: "objc-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if trimmed.hasPrefix("@interface") || trimmed.hasPrefix("@implementation") ||
           trimmed.range(of: #"^[+-]\s*\([^)]*\)\s*[A-Za-z_][A-Za-z0-9_:]*"#, options: .regularExpression) != nil {
            return makeTOCItem(id: "objc-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func cFamilyTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("#pragma mark") || trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("// region") {
            return makeTOCItem(id: "c-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(class|struct|enum|namespace|template)\b"#,
            #"^([A-Za-z_][\w:<>\*&\s]+)\s+[A-Za-z_~][A-Za-z0-9_:~]*\s*\([^;]*\)\s*(const)?\s*(\{|$)"#
        ]
        if patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "c-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func csharpTOCItem(for line: String, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("// MARK:") || trimmed.hasPrefix("#region") {
            return makeTOCItem(id: "cs-mark-\(index)", title: trimmed, line: index + 1, language: language)
        }
        let patterns = [
            #"^(public|private|protected|internal|abstract|sealed|static|partial|\s)*\s*(class|struct|interface|enum|record)\s+[A-Za-z_][A-Za-z0-9_]*"#,
            #"^(public|private|protected|internal|static|virtual|override|async|sealed|abstract|partial|\s)+[\w<>\[\], ?]+\s+[A-Za-z_][A-Za-z0-9_]*\s*\("#,
            #"^(public|private|protected|internal|static|readonly|const|\s)+[\w<>\[\], ?]+\s+[A-Za-z_][A-Za-z0-9_]*\s*(=|\{)"#
        ]
        if leadingIndentSpaces(in: line) <= 8, patterns.contains(where: { trimmed.range(of: $0, options: .regularExpression) != nil }) {
            return makeTOCItem(id: "cs-\(index)", title: trimmed, line: index + 1, language: language)
        }
        return nil
    }

    private static func markupTOCItem(for line: String, previousLine: String?, index: Int, language: String) -> TOCItem? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if language == "markdown" {
            if trimmed.range(of: #"^#{1,6}\s+\S"#, options: .regularExpression) != nil {
                return makeTOCItem(id: "markdown-\(index)", title: trimmed, line: index + 1, language: language)
            }
            if trimmed.range(of: #"^(-{3,}|={3,})$"#, options: .regularExpression) != nil,
               let previous = previousLine?.trimmingCharacters(in: .whitespaces),
               !previous.isEmpty,
               !previous.hasPrefix("#"),
               !previous.hasPrefix("```") {
                let marker = trimmed.first == "=" ? "# " : "## "
                return makeTOCItem(id: "markdown-setext-\(index)", title: marker + previous, line: index, language: language)
            }
            return nil
        }
        if language == "html",
           trimmed.range(of: #"<h[1-6][^>]*>.*</h[1-6]>"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return makeTOCItem(id: "html-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if language == "css",
           leadingIndentSpaces(in: line) == 0,
           trimmed.hasSuffix("{"),
           !trimmed.hasPrefix("@media") {
            return makeTOCItem(id: "css-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if language == "json",
           leadingIndentSpaces(in: line) <= 4,
           trimmed.range(of: #"^"[^"]+"\s*:\s*(\{|\[)"#, options: .regularExpression) != nil {
            return makeTOCItem(id: "json-\(index)", title: trimmed, line: index + 1, language: language)
        }
        if language == "csv", index == 0 {
            return makeTOCItem(id: "csv-header", title: "Header row", line: 1, language: language)
        }
        return nil
    }

    private static func leadingIndentSpaces(in line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.reduce(0) { total, character in
            total + (character == "\t" ? 4 : 1)
        }
    }

    private static func swiftLineLooksLikeProperty(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ")
    }

    private static func placeholderTOCItem(id: String, title: String) -> TOCItem {
        TOCItem(id: id, title: title, line: nil, level: 1, kind: .placeholder)
    }

    private static let tocLargeContentUTF16Threshold = 400_000

    private static func makeTOCItem(id: String, title: String, line: Int, language: String) -> TOCItem {
        let metadata = tocMetadata(for: title, language: language)
        return TOCItem(
            id: id,
            title: metadata.title,
            line: line,
            level: metadata.level,
            kind: metadata.kind
        )
    }

    private static func tocMetadata(for rawTitle: String, language: String) -> (title: String, level: Int, kind: TOCItemKind) {
        let title = rawTitle.trimmingCharacters(in: .whitespaces)
        if language == "markdown", title.hasPrefix("#") {
            let level = min(max(title.prefix { $0 == "#" }.count, 1), 6)
            let displayTitle = title.dropFirst(level).trimmingCharacters(in: .whitespaces)
            return (displayTitle.isEmpty ? title : displayTitle, level, .heading)
        }
        if title.hasPrefix("<h"),
           let levelCharacter = title.dropFirst(2).first,
           let level = Int(String(levelCharacter)) {
            return (title, min(max(level, 1), 6), .heading)
        }
        if title.hasPrefix("// MARK:") || title.hasPrefix("//MARK:") || title.hasPrefix("# MARK:") {
            let displayTitle = title.replacingOccurrences(of: "// MARK:", with: "")
                .replacingOccurrences(of: "//MARK:", with: "")
                .replacingOccurrences(of: "# MARK:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (displayTitle.isEmpty ? title : displayTitle, 1, .comment)
        }
        if title.hasPrefix("class ") || title.hasPrefix("struct ") || title.hasPrefix("enum ") ||
           title.hasPrefix("actor ") || title.hasPrefix("protocol ") || title.hasPrefix("extension ") ||
           title.hasPrefix("interface ") || title.hasPrefix("trait ") || title.hasPrefix("@interface") ||
           title.hasPrefix("@implementation") || title.hasPrefix("object ") || title.hasPrefix("type ") ||
           title.hasPrefix("impl ") || title.hasPrefix("module ") || title.contains(" class ") ||
           title.contains(" struct ") || title.contains(" enum ") || title.contains(" actor ") ||
           title.contains(" protocol ") || title.contains(" extension ") {
            return (title, 1, .type)
        }
        if title.hasPrefix("let ") || title.hasPrefix("var ") || title.hasPrefix("param(") ||
           title.contains(" let ") || title.contains(" var ") {
            return (title, 2, .property)
        }
        if title.contains("(") || title.hasPrefix("func ") || title.hasPrefix("def ") ||
           title.hasPrefix("fn ") || title.hasPrefix("fun ") || title.hasPrefix("function ") ||
           title.contains(" func ") {
            return (title, 2, .function)
        }
        return (title, 1, .content)
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
    let showHiddenFiles: Bool
    let ignoredFolderNamesRaw: Binding<String>
    let translucentBackgroundEnabled: Bool
    let boundaryEdge: HorizontalEdge?
    let onOpenFile: () -> Void
    let onOpenFolder: () -> Void
    let onOpenProjectFolder: (URL) -> Void
    let onToggleSupportedFilesOnly: (Bool) -> Void
    let onToggleHiddenFiles: (Bool) -> Void
    let onOpenProjectFile: (URL) -> Void
    let onRefreshTree: () -> Void
    let onCreateProjectFile: (URL?) -> Void
    let onCreateProjectFolder: (URL?) -> Void
    let onRenameProjectItem: (URL) -> Void
    let onDuplicateProjectItem: (URL) -> Void
    let onDeleteProjectItem: (URL) -> Void
    let onToggleGitTab: (() -> Void)?
    let onShowGitDiff: (@MainActor (String, String, String, String, String) -> Void)?
    let findInFilesQuery: Binding<String>
    let findInFilesCaseSensitive: Binding<Bool>
    let findInFilesReplaceQuery: Binding<String>
    let findInFilesSelectedMatchIDs: Binding<Set<String>>
    let findInFilesResults: [FindInFilesMatch]
    let findInFilesStatusMessage: String
    let findInFilesSourceMessage: String
    let isApplyingFindInFilesReplace: Bool
    let onFindInFilesSearch: () -> Void
    let onFindInFilesClear: () -> Void
    let onToggleFindInFilesSelection: (String) -> Void
    let onSelectAllFindInFilesMatches: () -> Void
    let onSelectNoFindInFilesMatches: () -> Void
    let onApplyFindInFilesReplace: () -> Void
    let onCancelFindInFilesReplace: () -> Void
    let onSelectFindInFilesMatch: (FindInFilesMatch) -> Void
    var keepsFindInFilesOpenOnSelect: Bool = true
    let activateFindInFilesToken: Int
    let activateTerminalToken: Int
    let compareDiffPresentation: DocumentDiffPresentation?
    let onCloseCompareDiff: () -> Void
    let revealURL: URL?
    let gitFileStatusMap: [String: GitFileStatus]
    var gitViewModel: GitViewModel?
    @State private var expandedDirectories: Set<String> = []
    @State private var hoveredNodeID: String? = nil
    @State private var fileIconStyleCache: [String: FileIconStyle] = [:]
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#if os(macOS)
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#endif
    @AppStorage("SettingsProjectSidebarDensity") private var sidebarDensityRaw: String = SidebarDensity.compact.rawValue
    @AppStorage("SettingsProjectSidebarAutoCollapseDeep") private var autoCollapseDeepFolders: Bool = true
    @AppStorage("SettingsProjectSidebarDisclosureSymbolStyle") private var disclosureSymbolStyleRaw: String = SidebarDisclosureSymbolStyle.chevron.rawValue

    @State private var activeTab: ProjectSidebarTab = .files
#if os(macOS)
    @State private var terminalCommand: String = ""
    @State private var terminalOutput: String = ""
    @State private var terminalIsRunning: Bool = false
#endif

    enum ProjectSidebarTab: String {
        case files
        case search
        case diff
        case git
#if os(macOS)
        case terminal
#endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            selectedTabContent
        }
        .padding(sidebarOuterPadding)
        .background(sidebarContainerShape.fill(sidebarSurfaceFill))
        .overlay(sidebarContainerBorderOverlay)
        .clipShape(sidebarContainerShape)
        .padding(sidebarCardOuterPadding)
        .onAppear {
            refreshFileIconStyleCache()
            revealTargetIfNeeded()
#if os(macOS)
            if activateTerminalToken != 0 {
                activeTab = .terminal
            } else if activateFindInFilesToken != 0 {
                activeTab = .search
            } else if compareDiffPresentation != nil {
                activeTab = .diff
            }
#else
            if activateFindInFilesToken != 0 {
                activeTab = .search
            } else if compareDiffPresentation != nil {
                activeTab = .diff
            }
#endif
        }
        .onChange(of: revealPath) { _, _ in revealTargetIfNeeded() }
        .onChange(of: projectTreeIconSignature) { _, _ in
            refreshFileIconStyleCache()
            revealTargetIfNeeded()
        }
        .onChange(of: activateFindInFilesToken) { _, _ in
            activeTab = .search
        }
#if os(macOS)
        .onChange(of: activateTerminalToken) { _, _ in
            activeTab = .terminal
        }
#endif
        .onChange(of: compareDiffPresentation?.id) { _, newValue in
            if newValue != nil {
                activeTab = .diff
            } else if activeTab == .diff {
                activeTab = .files
            }
        }
#if os(macOS)
        .overlay(alignment: boundaryEdge == .leading ? .leading : .trailing) {
            EmptyView()
        }
#endif
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch activeTab {
        case .files:
            filesContent
        case .search:
            findInFilesContent
        case .diff:
            compareDiffContent
        case .git:
            gitContent
#if os(macOS)
        case .terminal:
            IntegratedTerminalContent(
                rootFolderURL: rootFolderURL,
                command: $terminalCommand,
                output: $terminalOutput,
                isRunning: $terminalIsRunning
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: isCompactWidth ? 6 : 6) {
                tabButton(title: "Files", icon: "folder", tab: .files)
                tabButton(title: "Search", icon: "text.magnifyingglass", tab: .search)
                if compareDiffPresentation != nil {
                    tabButton(title: "Diff", icon: "rectangle.split.2x1", tab: .diff)
                }
                if gitViewModel != nil {
                    tabButton(title: "Git", icon: "arrow.triangle.branch", tab: .git)
                }
#if os(macOS)
                tabButton(title: "Terminal", icon: "terminal", tab: .terminal)
#endif
            }
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.065))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func tabButton(title: String, icon: String, tab: ProjectSidebarTab) -> some View {
        let isSelected = activeTab == tab
        let cardShape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return Button {
            activeTab = tab
        } label: {
            Label(title, systemImage: icon)
                .font((isCompactWidth ? Font.caption : Font.subheadline).weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, isCompactWidth ? 6 : 10)
                .frame(minWidth: isCompactWidth ? 58 : 50, maxWidth: .infinity, minHeight: isCompactWidth ? 36 : 40, alignment: .center)
                .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .background(
            cardShape
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.09))
        )
        .overlay(
            cardShape
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .help(NSLocalizedString(title, comment: "Project sidebar tab help"))
        .accessibilityLabel(NSLocalizedString(title, comment: "Project sidebar tab accessibility label"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var filesContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsSidebarActionsRow {
                VStack(alignment: .leading, spacing: isCompactDensity ? 6 : 8) {
                    HStack(spacing: isCompactDensity ? 8 : 10) {
                        Button(action: onOpenFolder) {
                            sidebarActionIcon("folder")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Open Folder…", comment: "Project sidebar open folder action"))
                        .accessibilityLabel(NSLocalizedString("Open folder", comment: "Project sidebar open folder accessibility label"))
                        .accessibilityHint(NSLocalizedString("Select a project folder to show in the sidebar", comment: "Project sidebar open folder accessibility hint"))

                        if !RecentProjectFoldersStore.items(limit: 5).isEmpty {
                            Menu {
                                ForEach(RecentProjectFoldersStore.items(limit: 5)) { item in
                                    Button {
                                        onOpenProjectFolder(item.url)
                                    } label: {
                                        Label(item.title, systemImage: "folder")
                                    }
                                    .help(item.subtitle)
                                }
                            } label: {
                                sidebarActionIcon("clock.arrow.circlepath")
                            }
                            .buttonStyle(.borderless)
                            .help(NSLocalizedString("Recent Project Folders", comment: "Project sidebar recent folders help"))
                            .accessibilityLabel(NSLocalizedString("Recent project folders", comment: "Project sidebar recent folders accessibility label"))
                        }

                        Button(action: onOpenFile) {
                            sidebarActionIcon("doc")
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
                            sidebarActionIcon("plus")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Create in Project Root", comment: "Project sidebar create action"))
                        .accessibilityLabel(NSLocalizedString("Create project item", comment: "Project sidebar create accessibility label"))
                        .accessibilityHint(NSLocalizedString("Creates a new file or folder in the project root", comment: "Project sidebar create accessibility hint"))

                        Button(action: onRefreshTree) {
                            sidebarActionIcon("arrow.clockwise")
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
                            Button {
                                onToggleHiddenFiles(!showHiddenFiles)
                            } label: {
                                Label(
                                    NSLocalizedString("Show Hidden Files", comment: "Project sidebar hidden files filter label"),
                                    systemImage: showHiddenFiles ? "checkmark.circle.fill" : "circle"
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
                            Menu(NSLocalizedString("Ignored Folders", comment: "Project sidebar ignored folders menu")) {
                                ForEach(ProjectIgnoredFolders.knownNames, id: \.self) { name in
                                    Button {
                                        toggleIgnoredFolderName(name)
                                    } label: {
                                        Label(name, systemImage: ignoredFolderNames.contains(name) ? "checkmark.circle.fill" : "circle")
                                    }
                                }
                            }
                            Divider()
                            Button(NSLocalizedString("Expand All", comment: "Project sidebar expand all action")) {
                                expandAllDirectories()
                            }
                            Button(NSLocalizedString("Collapse All", comment: "Project sidebar collapse all action")) {
                                collapseAllDirectories()
                            }
                        } label: {
                            sidebarActionIcon("arrow.up.arrow.down.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(NSLocalizedString("Expand or Collapse All", comment: "Project sidebar expand/collapse help"))
                        .accessibilityLabel(NSLocalizedString("Expand or collapse all folders", comment: "Project sidebar expand/collapse accessibility label"))
                        .accessibilityHint(NSLocalizedString("Expands or collapses all folders in the project tree", comment: "Project sidebar expand/collapse accessibility hint"))

                        Spacer(minLength: 0)
                    }
                    .font(.system(size: isCompactDensity ? 13 : 14, weight: .medium))

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(sidebarSeparatorColor.opacity(0.55))
                        .frame(height: 1)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, headerHorizontalPadding)
                .padding(.top, isCompactDensity ? 4 : 6)
                .padding(.bottom, headerBottomPadding)
#if os(macOS)
                .background(sidebarHeaderFill)
#endif
            }

            if let rootFolderURL {
                projectPathCard(rootFolderURL)
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
    }

    private func sidebarActionIcon(_ systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.08))
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: isCompactDensity ? 13 : 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .frame(width: isCompactDensity ? 30 : 32, height: isCompactDensity ? 28 : 30)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func projectPathCard(_ rootFolderURL: URL) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "folder.fill")
                .font(.system(size: isCompactDensity ? 13 : 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(rootFolderURL.lastPathComponent)
                    .font(.system(size: isCompactDensity ? 12 : 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(rootFolderURL.deletingLastPathComponent().path)
                    .font(.system(size: isCompactDensity ? 10 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompactDensity ? 7 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.secondary.opacity(0.075))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color.secondary.opacity(0.13), lineWidth: 1)
        )
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project folder \(rootFolderURL.lastPathComponent)")
        .accessibilityHint(rootFolderURL.path)
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

    private var findInFilesContent: some View {
        FindInFilesPanel(
            query: findInFilesQuery,
            caseSensitive: findInFilesCaseSensitive,
            replaceQuery: findInFilesReplaceQuery,
            selectedMatchIDs: findInFilesSelectedMatchIDs,
            results: findInFilesResults,
            statusMessage: findInFilesStatusMessage,
            sourceMessage: findInFilesSourceMessage,
            isApplyingReplace: isApplyingFindInFilesReplace,
            onSearch: onFindInFilesSearch,
            onClear: onFindInFilesClear,
            onToggleSelection: onToggleFindInFilesSelection,
            onSelectAll: onSelectAllFindInFilesMatches,
            onSelectNone: onSelectNoFindInFilesMatches,
            onApplyReplace: onApplyFindInFilesReplace,
            onCancelReplace: onCancelFindInFilesReplace,
            onSelect: onSelectFindInFilesMatch,
            onClose: { activeTab = .files },
            closesOnSelect: !keepsFindInFilesOpenOnSelect
        )
        .environment(\.searchPanelTranslucencyOverride, translucentBackgroundEnabled)
        .environment(\.searchPanelEmbeddedInSidebar, true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var compareDiffContent: some View {
        if let presentation = compareDiffPresentation {
            SidebarCompareDiffView(
                presentation: presentation,
                onClose: onCloseCompareDiff
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Diff", systemImage: "rectangle.split.2x1")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var gitContent: some View {
        Group {
            if let vm = gitViewModel {
                GitTabView(
                    gitViewModel: vm,
                    translucentBackgroundEnabled: translucentBackgroundEnabled,
                    onShowDiff: onShowGitDiff
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Git Repository", systemImage: "arrow.triangle.branch")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        22
#else
        20
#endif
    }

    private var isCompactWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private var sidebarContainerShape: AnyShape {
#if os(macOS)
        AnyShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
#elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            AnyShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
        } else {
            AnyShape(
                RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous)
            )
        }
#else
        AnyShape(RoundedRectangle(cornerRadius: sidebarCornerRadius, style: .continuous))
#endif
    }

    @ViewBuilder
    private var sidebarContainerBorderOverlay: some View {
#if os(macOS)
        sidebarContainerShape.stroke(sidebarSurfaceStroke, lineWidth: 1.2)
#elseif os(iOS)
        sidebarContainerShape.stroke(sidebarSurfaceStroke, lineWidth: 1.2)
#else
        sidebarContainerShape.stroke(sidebarSurfaceStroke, lineWidth: 1.2)
#endif
    }

    private var sidebarOuterPadding: CGFloat {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? 8 : 10
#else
        8
#endif
    }

    private var sidebarCardOuterPadding: EdgeInsets {
#if os(macOS)
        EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)
#else
        EdgeInsets()
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
            let style = cachedFileIconStyle(for: node.url)
            let isSelected = selectedFileURL?.standardizedFileURL == node.url.standardizedFileURL
            let isHovered = hoveredNodeID == node.id
            let gitRelPath: String = {
                guard let root = rootFolderURL?.standardizedFileURL.path else { return "" }
                let filePath = node.url.standardizedFileURL.path
                guard filePath.hasPrefix(root) else { return "" }
                return String(filePath.dropFirst(root.count + 1))
            }()
            let gitStatus = gitFileStatusMap[gitRelPath]
            return AnyView(
                Button {
                    onOpenProjectFile(node.url)
                } label: {
                    HStack(spacing: 6) {
                        if let status = gitStatus {
                            Image(systemName: status.displayIcon)
                                .font(.caption2)
                                .foregroundStyle(gitStatusColor(status))
                                .frame(width: 14)
                        }
                        Image(systemName: style.symbol)
                            .foregroundStyle(fileIconColor(style: style, isSelected: isSelected, isHovered: isHovered))
                            .symbolRenderingMode(.hierarchical)
                            .opacity(gitStatus != nil ? 0.7 : 1)
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
                    .background(gitStatus != nil ? gitStatusColor(gitStatus!).opacity(0.06) : Color.clear)
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
        isCompactDensity ? 3 : 4
    }

    private var directoryRowContentLeadingPadding: CGFloat {
        0
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
            let base: CGFloat = isCompactDensity ? 0 : 4
            return translucentBackgroundEnabled ? base + 2 : base
#else
            return isCompactDensity ? 0 : 4
#endif
        }()
        return EdgeInsets(
            top: projectListRowInsetVertical,
            leading: macLeadingInset,
            bottom: projectListRowInsetVertical,
            trailing: isCompactDensity ? 10 : 12
        )
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
        baseInset = level == 0 ? 0 : 5
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

    private var projectListRowInsetVertical: CGFloat {
        2
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
#if os(iOS)
        if isDirectory, level == 0 {
            return isCompactDensity ? 0.25 : 0.5
        }
#else
        _ = level
        _ = isDirectory
#endif
        return isCompactDensity ? 0.5 : 1
    }

    private func folderIconColor(isHovered: Bool) -> Color {
        if isHovered {
            return Color.accentColor
        }
        return translucentBackgroundEnabled ? Color.accentColor.opacity(0.92) : Color.accentColor.opacity(0.96)
    }

    private func gitStatusColor(_ status: GitFileStatus) -> Color {
        switch status {
        case .added, .copied: return .green
        case .modified: return .purple
        case .deleted: return .red
        case .renamed: return .cyan
        case .conflicted, .untracked: return .orange
        case .clean: return .secondary
        }
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
        isCompactDensity ? 20 : 22
    }

    private var ignoredFolderNames: Set<String> {
        ProjectIgnoredFolders.names(from: ignoredFolderNamesRaw.wrappedValue)
    }

    private func toggleIgnoredFolderName(_ name: String) {
        var names = ignoredFolderNames
        if names.contains(name) {
            names.remove(name)
        } else {
            names.insert(name)
        }
        ignoredFolderNamesRaw.wrappedValue = ProjectIgnoredFolders.rawValue(from: names)
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

    private var projectTreeIconSignature: String {
        projectTreeIconSignature(for: nodes)
    }

    private func projectTreeIconSignature(for nodes: [ProjectTreeNode]) -> String {
        nodes.map { node in
            let path = node.url.standardizedFileURL.path
            guard node.isDirectory else { return path }
            return "\(path)[\(projectTreeIconSignature(for: node.children))]"
        }
        .joined(separator: "|")
    }

    private func refreshFileIconStyleCache() {
        var cache: [String: FileIconStyle] = [:]
        collectFileIconStyles(from: nodes, into: &cache)
        fileIconStyleCache = cache
    }

    private func collectFileIconStyles(from nodes: [ProjectTreeNode], into cache: inout [String: FileIconStyle]) {
        for node in nodes {
            if node.isDirectory {
                collectFileIconStyles(from: node.children, into: &cache)
            } else {
                cache[node.url.standardizedFileURL.path] = fileIconStyle(for: node.url)
            }
        }
    }

    private func cachedFileIconStyle(for url: URL) -> FileIconStyle {
        fileIconStyleCache[url.standardizedFileURL.path] ?? fileIconStyle(for: url)
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

private struct SidebarCompareDiffView: View {
    let presentation: DocumentDiffPresentation
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(presentation.changedRows) { row in
                        diffRow(row)
                    }
                    if presentation.changedRows.isEmpty {
                        ContentUnavailableView("No Changes", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(isCompactWidth ? 8 : 12)
            }
            .background(Color.clear)
        }
        .background(Color.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(presentation.title), comparing \(presentation.leftTitle) with \(presentation.rightTitle)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(presentation.title)
                        .font(isCompactWidth ? .subheadline.weight(.semibold) : .headline)
                        .lineLimit(isCompactWidth ? 2 : 1)
                        .truncationMode(.middle)
                    Text("\(presentation.diff.hunks.count) changes")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button(action: onClose) {
                    if isCompactWidth {
                        Image(systemName: "xmark.circle.fill")
                    } else {
                        Text("Close")
                    }
                }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Close diff")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text(presentation.leftTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "arrow.left.and.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(presentation.rightTitle)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }
        }
        .padding(isCompactWidth ? 8 : 12)
    }

    private func diffRow(_ row: DocumentDiff.Row) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if row.kind == .removed || row.kind == .changed {
                line(prefix: "- \(row.leftLineNumber.map(String.init) ?? "")", text: row.leftText, color: .red)
            }
            if row.kind == .inserted || row.kind == .changed {
                line(prefix: "+ \(row.rightLineNumber.map(String.init) ?? "")", text: row.rightText, color: .green)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground(for: row), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func line(prefix: String, text: String, color: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .firstTextBaseline, spacing: isCompactWidth ? 6 : 8) {
                Text(prefix)
                    .font(.caption2.monospaced())
                    .foregroundStyle(color)
                    .frame(width: isCompactWidth ? 36 : 46, alignment: .leading)
                Text(text.isEmpty ? " " : text)
                    .font((isCompactWidth ? Font.caption2 : Font.caption).monospaced())
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var isCompactWidth: Bool {
#if os(iOS)
        horizontalSizeClass == .compact
#else
        false
#endif
    }

    private func rowBackground(for row: DocumentDiff.Row) -> Color {
        switch row.kind {
        case .removed:
            return Color.red.opacity(colorScheme == .dark ? 0.18 : 0.10)
        case .inserted:
            return Color.green.opacity(colorScheme == .dark ? 0.18 : 0.10)
        case .changed:
            return Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.12)
        case .equal:
            return Color.clear
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

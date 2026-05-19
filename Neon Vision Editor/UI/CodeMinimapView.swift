import SwiftUI

// MARK: - Code Minimap Model

enum CodeMinimapMarkerKind: Int, Sendable {
    case code
    case importLine
    case property
    case controlFlow
    case declaration
    case comment
    case section
}

struct CodeMinimapMarker: Identifiable, Equatable, Sendable {
    let id: Int
    let line: Int
    let startFraction: Double
    let widthFraction: Double
    let kind: CodeMinimapMarkerKind
}

struct CodeMinimapSnapshot: Equatable, Sendable {
    nonisolated static let empty = CodeMinimapSnapshot(totalLines: 1, markers: [], isTruncated: false)

    let totalLines: Int
    let markers: [CodeMinimapMarker]
    let isTruncated: Bool
}

struct CodeMinimapViewport: Equatable, Sendable {
    let topFraction: Double
    let heightFraction: Double
}

nonisolated func codeMinimapViewport(
    visibleY: Double,
    visibleHeight: Double,
    contentHeight: Double
) -> CodeMinimapViewport {
    let safeVisibleHeight = max(1, visibleHeight)
    let safeContentHeight = max(safeVisibleHeight, contentHeight)
    guard safeContentHeight > safeVisibleHeight else {
        return CodeMinimapViewport(topFraction: 0, heightFraction: 1)
    }
    let maxOffset = max(1, safeContentHeight - safeVisibleHeight)
    let top = min(max(0, visibleY / maxOffset), 1)
    let height = min(max(safeVisibleHeight / safeContentHeight, 0.02), 1)
    return CodeMinimapViewport(topFraction: top, heightFraction: height)
}

nonisolated func codeMinimapScrollOffset(
    topFraction: Double?,
    contentHeight: Double,
    visibleHeight: Double
) -> Double {
    guard contentHeight > visibleHeight else { return 0 }
    let top = min(max(0, topFraction ?? 0), 1)
    return top * max(0, contentHeight - visibleHeight)
}

nonisolated func supportsCodeMinimap(language: String) -> Bool {
    let lang = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let nonCodeLanguages: Set<String> = [
        "plain",
        "standard",
        "markdown",
        "csv",
        "tsv",
        "log",
        "ipynb"
    ]
    return !lang.isEmpty && !nonCodeLanguages.contains(lang)
}

nonisolated func buildCodeMinimapSnapshot(
    text: String,
    language: String,
    maxUTF16Length: Int = 320_000,
    maxLines: Int = 12_000
) -> CodeMinimapSnapshot {
    guard supportsCodeMinimap(language: language), !text.isEmpty else {
        return CodeMinimapSnapshot(totalLines: 1, markers: [], isTruncated: false)
    }

    var markers: [CodeMinimapMarker] = []
    markers.reserveCapacity(1024)

    let commentPrefixes = codeMinimapCommentPrefixes(language: language)
    let maxUnits = max(0, maxUTF16Length)
    var consumedUnits = 0
    var lineNumber = 1
    var truncated = false

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let lineUnits = rawLine.utf16.count + 1
        if consumedUnits + lineUnits > maxUnits || lineNumber > maxLines {
            truncated = true
            break
        }
        consumedUnits += lineUnits

        let trimmed = String(rawLine).trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            let leadingWhitespace = rawLine.prefix { $0 == " " || $0 == "\t" }
            let indentUnits = leadingWhitespace.reduce(0) { partial, character in
                partial + (character == "\t" ? 4 : 1)
            }
            let contentUnits = max(1, min(trimmed.count, 96))
            let kind = codeMinimapMarkerKind(for: String(trimmed), commentPrefixes: commentPrefixes)
            let marker = CodeMinimapMarker(
                id: lineNumber,
                line: lineNumber,
                startFraction: min(Double(indentUnits) / 64.0, 0.78),
                widthFraction: max(0.10, min(Double(contentUnits) / 96.0, 1.0)),
                kind: kind
            )
            markers.append(marker)
        }
        lineNumber += 1
    }

    return CodeMinimapSnapshot(
        totalLines: max(1, lineNumber - 1),
        markers: markers,
        isTruncated: truncated
    )
}

private nonisolated func codeMinimapCommentPrefixes(language: String) -> [String] {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "python", "ruby", "bash", "zsh", "powershell", "yaml", "yml", "toml":
        return ["#"]
    case "html", "xml", "svg", "xhtml":
        return ["<!--"]
    case "sql":
        return ["--", "/*", "*"]
    default:
        return ["//", "/*", "*"]
    }
}

private nonisolated func codeMinimapMarkerKind(
    for trimmedLine: String,
    commentPrefixes: [String]
) -> CodeMinimapMarkerKind {
    let upper = trimmedLine.uppercased()
    if upper.contains("MARK:") ||
        upper.contains("TODO:") ||
        upper.contains("FIXME:") ||
        upper.contains("SECTION") ||
        upper.contains("#PRAGMA MARK") {
        return .section
    }
    if commentPrefixes.contains(where: { trimmedLine.hasPrefix($0) }) {
        return .comment
    }
    if isCodeMinimapImportLine(trimmedLine) {
        return .importLine
    }
    if isCodeMinimapDeclarationLine(trimmedLine) {
        return .declaration
    }
    if isCodeMinimapPropertyLine(trimmedLine) {
        return .property
    }
    if isCodeMinimapControlFlowLine(trimmedLine) {
        return .controlFlow
    }
    return .code
}

private nonisolated func isCodeMinimapImportLine(_ trimmedLine: String) -> Bool {
    let lower = trimmedLine.lowercased()
    let prefixes = [
        "import ",
        "#include ",
        "using ",
        "package ",
        "require ",
        "from "
    ]
    return prefixes.contains { lower.hasPrefix($0) }
}

private nonisolated func isCodeMinimapDeclarationLine(_ trimmedLine: String) -> Bool {
    let lower = trimmedLine.lowercased()
    let declarationPrefixes = [
        "func ",
        "private func ",
        "public func ",
        "static func ",
        "struct ",
        "class ",
        "enum ",
        "protocol ",
        "extension ",
        "actor ",
        "def ",
        "function ",
        "interface ",
        "type ",
        "impl ",
        "fn "
    ]
    return declarationPrefixes.contains { lower.hasPrefix($0) }
}

private nonisolated func isCodeMinimapPropertyLine(_ trimmedLine: String) -> Bool {
    let lower = trimmedLine.lowercased()
    let prefixes = [
        "let ",
        "var ",
        "const ",
        "static let ",
        "static var ",
        "private let ",
        "private var ",
        "public let ",
        "public var ",
        "final let ",
        "final var "
    ]
    return prefixes.contains { lower.hasPrefix($0) }
}

private nonisolated func isCodeMinimapControlFlowLine(_ trimmedLine: String) -> Bool {
    let lower = trimmedLine.lowercased()
    let prefixes = [
        "if ",
        "else ",
        "guard ",
        "for ",
        "while ",
        "switch ",
        "case ",
        "catch ",
        "do ",
        "return ",
        "throw ",
        "await "
    ]
    return prefixes.contains { lower.hasPrefix($0) }
}

// MARK: - Code Minimap View

struct CodeMinimapView: View {
    let text: String
    let language: String
    let colorScheme: ColorScheme
    let isLargeFileMode: Bool
    let viewport: CodeMinimapViewport?
    let onSelectLine: (Int) -> Void

    @State private var snapshot: CodeMinimapSnapshot = .empty
    @State private var snapshotTask: Task<Void, Never>?
    @State private var lastSelectedLine: Int = 0

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)

                Canvas { context, size in
                    guard size.width > 4, size.height > 4 else { return }
                    let contentHeight = minimapContentHeight(visibleHeight: size.height)
                    let scrollOffset = minimapScrollOffset(contentHeight: contentHeight, visibleHeight: size.height)
                    let totalLines = max(1, snapshot.totalLines)
                    let lineHeight = max(1.0, contentHeight / CGFloat(totalLines))
                    for marker in snapshot.markers {
                        let y = CGFloat(marker.line - 1) * lineHeight - scrollOffset
                        guard y >= -3, y <= size.height + 3 else { continue }
                        let x = 4 + CGFloat(marker.startFraction) * (size.width - 10)
                        let width = max(5, CGFloat(marker.widthFraction) * (size.width - x - 4))
                        let rect = CGRect(x: x, y: y, width: width, height: max(1, min(3, lineHeight)))
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color(for: marker.kind)))
                    }

                    if snapshot.isTruncated {
                        let rect = CGRect(x: 4, y: size.height - 5, width: size.width - 8, height: 2)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.orange.opacity(0.8)))
                    }

                    let borderRect = CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1)
                    context.stroke(Path(roundedRect: borderRect, cornerRadius: 6), with: .color(borderColor), lineWidth: 1)
                }
                .padding(.vertical, 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        selectLine(at: value.location.y, height: geometry.size.height)
                    }
                    .onEnded { value in
                        selectLine(at: value.location.y, height: geometry.size.height)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Code minimap")
            .accessibilityValue(snapshot.isTruncated ? "Large file preview" : "\(snapshot.totalLines) lines")
            .accessibilityHint("Tap or drag to scroll the editor to a line. The minimap follows the editor scroll position and color-codes sections, declarations, imports, properties, control flow, and comments.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    selectAccessibleLine(delta: 20)
                case .decrement:
                    selectAccessibleLine(delta: -20)
                @unknown default:
                    break
                }
            }
        }
        .frame(width: 144)
        .padding(.vertical, 6)
        .padding(.trailing, 6)
        .task(id: minimapSignature) {
            snapshotTask?.cancel()
            let textSnapshot = text
            let languageSnapshot = language
            let shouldUseLargeFileCap = isLargeFileMode
            let task = Task(priority: .utility) {
                let nextSnapshot = await Task.detached(priority: .utility) {
                    buildCodeMinimapSnapshot(
                        text: textSnapshot,
                        language: languageSnapshot,
                        maxUTF16Length: shouldUseLargeFileCap ? 180_000 : 320_000,
                        maxLines: shouldUseLargeFileCap ? 6_000 : 12_000
                    )
                }.value
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    snapshot = nextSnapshot
                }
            }
            snapshotTask = task
        }
        .onDisappear {
            snapshotTask?.cancel()
            snapshotTask = nil
        }
    }

    private var minimapSignature: String {
        let prefix = text.prefix(160)
        let suffix = text.suffix(160)
        return "\(language)|\(isLargeFileMode)|\(text.utf16.count)|\(prefix)|\(suffix)"
    }

    private func color(for kind: CodeMinimapMarkerKind) -> Color {
        switch kind {
        case .code:
            return colorScheme == .dark ? Color.white.opacity(0.30) : Color.black.opacity(0.23)
        case .importLine:
            return Color.cyan.opacity(colorScheme == .dark ? 0.78 : 0.66)
        case .property:
            return Color.purple.opacity(colorScheme == .dark ? 0.76 : 0.62)
        case .controlFlow:
            return Color.yellow.opacity(colorScheme == .dark ? 0.78 : 0.70)
        case .declaration:
            return Color.accentColor.opacity(colorScheme == .dark ? 0.66 : 0.56)
        case .comment:
            return Color.green.opacity(colorScheme == .dark ? 0.74 : 0.64)
        case .section:
            return Color.orange.opacity(colorScheme == .dark ? 0.96 : 0.90)
        }
    }

    private func minimapContentHeight(visibleHeight: CGFloat) -> CGFloat {
        let lineDrivenHeight = CGFloat(max(1, snapshot.totalLines)) * 2.35 + 8
        return max(visibleHeight, min(lineDrivenHeight, 36_000))
    }

    private func minimapScrollOffset(contentHeight: CGFloat, visibleHeight: CGFloat) -> CGFloat {
        CGFloat(codeMinimapScrollOffset(
            topFraction: viewport?.topFraction,
            contentHeight: Double(contentHeight),
            visibleHeight: Double(visibleHeight)
        ))
    }

    private func selectLine(at yLocation: CGFloat, height: CGFloat) {
        let drawableHeight = max(1, height - 8)
        let adjustedY = min(max(0, yLocation - 4), drawableHeight)
        let contentHeight = minimapContentHeight(visibleHeight: drawableHeight)
        let scrollOffset = minimapScrollOffset(contentHeight: contentHeight, visibleHeight: drawableHeight)
        let ratio = min(max(0, (adjustedY + scrollOffset) / contentHeight), 1)
        let line = max(1, min(snapshot.totalLines, Int((ratio * CGFloat(max(1, snapshot.totalLines))).rounded(.up))))
        guard line != lastSelectedLine else { return }
        lastSelectedLine = line
        onSelectLine(line)
    }

    private func selectAccessibleLine(delta: Int) {
        let base = lastSelectedLine > 0 ? lastSelectedLine : 1
        let line = max(1, min(snapshot.totalLines, base + delta))
        lastSelectedLine = line
        onSelectLine(line)
    }
}

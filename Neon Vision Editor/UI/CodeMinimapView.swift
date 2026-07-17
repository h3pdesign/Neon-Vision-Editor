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

struct CodeMinimapViewportMarker: Equatable, Sendable {
    let yFraction: Double
    let heightFraction: Double
}

@MainActor
private final class CodeMinimapSnapshotCache {
    static let shared = CodeMinimapSnapshotCache()

    private var snapshots: [String: CodeMinimapSnapshot] = [:]
    private var accessOrder: [String] = []
    private let capacity = 24

    func snapshot(for key: String) -> CodeMinimapSnapshot? {
        guard let snapshot = snapshots[key] else { return nil }
        touch(key)
        return snapshot
    }

    func insert(_ snapshot: CodeMinimapSnapshot, for key: String) {
        snapshots[key] = snapshot
        touch(key)
        while accessOrder.count > capacity {
            let evictedKey = accessOrder.removeFirst()
            snapshots.removeValue(forKey: evictedKey)
        }
    }

    private func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}

nonisolated func codeMinimapViewportTopFraction(
    markerCenterYFraction: Double,
    viewportHeightFraction: Double,
    minimumHeightFraction: Double = 0.035
) -> Double {
    let markerHeight = min(max(viewportHeightFraction, minimumHeightFraction), 1)
    guard markerHeight < 1 else { return 0 }
    let center = min(max(markerCenterYFraction, 0), 1)
    let markerY = min(max(center - markerHeight / 2, 0), 1 - markerHeight)
    return min(max(markerY / max(0.0001, 1 - markerHeight), 0), 1)
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

nonisolated func codeMinimapViewportMarker(
    viewport: CodeMinimapViewport?,
    minimumHeightFraction: Double = 0.035
) -> CodeMinimapViewportMarker? {
    guard let viewport, viewport.heightFraction < 1 else { return nil }
    let markerHeight = min(max(viewport.heightFraction, minimumHeightFraction), 1)
    let top = min(max(viewport.topFraction, 0), 1)
    let y = min(top * max(0, 1 - markerHeight), 1 - markerHeight)
    return CodeMinimapViewportMarker(yFraction: y, heightFraction: markerHeight)
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
            let contentUnits = max(1, min(trimmed.utf16.count, 96))
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
    let snapshotCacheKey: String
    let text: String
    let language: String
    let colorScheme: ColorScheme
    let isLargeFileMode: Bool
    let viewport: CodeMinimapViewport?
    let onSelectLine: (Int) -> Void
    let onMoveViewport: (Double) -> Void

    @State private var snapshot: CodeMinimapSnapshot = .empty
    @State private var lastSelectedLine: Int = 0
    @State private var lastMovedViewportTop: Double = -1

    private var snapshotTaskID: String {
        "\(snapshotCacheKey)|\(isLargeFileMode ? "large" : "standard")|\(text.utf8.count)"
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06)
    }

    private var minimapShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                minimapShape
                    .fill(backgroundColor)
                    .overlay(
                        minimapShape
                            .stroke(borderColor, lineWidth: 0.75)
                    )

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
                }
                .padding(.vertical, 5)

                viewportMarkerOverlay
            }
            .clipShape(minimapShape)
            .contentShape(minimapShape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        moveViewportMarker(to: value.location.y, height: geometry.size.height)
                    }
                    .onEnded { value in
                        moveViewportMarker(to: value.location.y, height: geometry.size.height, force: true)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Code minimap")
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Tap or drag the viewport marker to scroll the editor. The minimap follows the editor scroll position and color-codes sections, declarations, imports, properties, control flow, and comments.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    moveAccessibleViewport(delta: 0.06)
                case .decrement:
                    moveAccessibleViewport(delta: -0.06)
                @unknown default:
                    break
                }
            }
        }
        .frame(width: 144)
        .padding(.vertical, 6)
        .padding(.trailing, 6)
        .task(id: snapshotTaskID) {
            guard !text.isEmpty else {
                snapshot = .empty
                return
            }
            if let cached = CodeMinimapSnapshotCache.shared.snapshot(for: snapshotCacheKey) {
                snapshot = cached
                return
            }
            let textSnapshot = text
            let languageSnapshot = language
            let shouldUseLargeFileCap = isLargeFileMode
            let nextSnapshot = await Task.detached(priority: .utility) {
                buildCodeMinimapSnapshot(
                    text: textSnapshot,
                    language: languageSnapshot,
                    maxUTF16Length: shouldUseLargeFileCap ? 180_000 : 320_000,
                    maxLines: shouldUseLargeFileCap ? 6_000 : 12_000
                )
            }.value
            guard !Task.isCancelled else { return }
            snapshot = nextSnapshot
            CodeMinimapSnapshotCache.shared.insert(nextSnapshot, for: snapshotCacheKey)
        }
    }

    private var accessibilityValue: String {
        if snapshot.isTruncated {
            return "Large file preview"
        }
        guard let marker = codeMinimapViewportMarker(viewport: viewport) else {
            return "\(snapshot.totalLines) lines"
        }
        let percent = Int((marker.yFraction * 100).rounded())
        return "\(snapshot.totalLines) lines, viewport near \(percent)%"
    }

    private var viewportMarkerOverlay: some View {
        GeometryReader { proxy in
            if let marker = codeMinimapViewportMarker(viewport: viewport) {
                let inset: CGFloat = 5
                let drawableHeight = max(1, proxy.size.height - inset * 2)
                let markerY = inset + CGFloat(marker.yFraction) * drawableHeight
                let markerHeight = max(8, CGFloat(marker.heightFraction) * drawableHeight)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(viewportMarkerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(viewportMarkerBorder, lineWidth: 1)
                    )
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(viewportMarkerAccent)
                            .frame(width: 2)
                            .padding(.vertical, 3)
                            .padding(.leading, 3)
                    }
                    .frame(width: max(0, proxy.size.width - 8), height: markerHeight)
                    .position(x: proxy.size.width / 2, y: markerY + markerHeight / 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .allowsHitTesting(false)
    }

    private var viewportMarkerFill: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.16)
    }

    private var viewportMarkerBorder: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.58 : 0.46)
    }

    private var viewportMarkerAccent: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.82 : 0.72)
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

    private func moveViewportMarker(to yLocation: CGFloat, height: CGFloat, force: Bool = false) {
        guard let viewport, viewport.heightFraction < 1 else {
            selectLine(at: yLocation, height: height)
            return
        }
        let inset: CGFloat = 5
        let drawableHeight = max(1, height - inset * 2)
        let centerYFraction = Double(min(max(0, yLocation - inset), drawableHeight) / drawableHeight)
        let topFraction = codeMinimapViewportTopFraction(
            markerCenterYFraction: centerYFraction,
            viewportHeightFraction: viewport.heightFraction
        )
        guard force || abs(topFraction - lastMovedViewportTop) > 0.003 else { return }
        lastMovedViewportTop = topFraction
        onMoveViewport(topFraction)
    }

    private func moveAccessibleViewport(delta: Double) {
        let currentTop = viewport?.topFraction ?? lastMovedViewportTop
        let topFraction = min(max(0, currentTop + delta), 1)
        lastMovedViewportTop = topFraction
        onMoveViewport(topFraction)
    }
}

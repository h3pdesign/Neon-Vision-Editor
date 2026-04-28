import SwiftUI

struct DiffComparisonView<Footer: View>: View {
    let title: String
    let leftTitle: String
    let rightTitle: String
    let diff: DocumentDiff
    let onClose: () -> Void
    @ViewBuilder let footer: () -> Footer

    @Environment(\.colorScheme) private var colorScheme
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
#if os(macOS)
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
    @AppStorage("SettingsMacTranslucencyMode") private var macTranslucencyModeRaw: String = "balanced"
#else
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = true
#endif
    @State private var selectedHunkIndex: Int = 0

    private var contentMinWidth: CGFloat {
#if os(macOS)
        1180
#else
        horizontalSizeClass == .compact ? 0 : 760
#endif
    }

    private var contentMinHeight: CGFloat {
#if os(macOS)
        760
#else
        horizontalSizeClass == .compact ? 420 : 560
#endif
    }

    private var columnWidth: CGFloat {
#if os(macOS)
        560
#else
        horizontalSizeClass == .compact ? 320 : 360
#endif
    }

    private var usesCompactHeader: Bool {
#if os(macOS)
        false
#else
        horizontalSizeClass == .compact
#endif
    }

    private var headerTitleFont: Font {
        usesCompactHeader ? .headline.weight(.semibold) : .title3.weight(.semibold)
    }

    private var headerActionFont: Font {
        usesCompactHeader ? .caption.weight(.semibold) : .body
    }

    private var headerHorizontalPadding: CGFloat {
        usesCompactHeader ? 14 : 24
    }

    private var headerVerticalPadding: CGFloat {
        usesCompactHeader ? 12 : 18
    }

    private var currentHunkLabel: String {
        guard !diff.hunks.isEmpty else { return "No changes" }
        return "Change \(selectedHunkIndex + 1) of \(diff.hunks.count)"
    }

    private var surfaceBackgroundStyle: AnyShapeStyle {
#if os(macOS)
        if translucentWindow {
            switch macTranslucencyModeRaw {
            case "subtle":
                return AnyShapeStyle(Material.thickMaterial.opacity(0.72))
            case "vibrant":
                return AnyShapeStyle(Material.ultraThinMaterial.opacity(0.62))
            default:
                return AnyShapeStyle(Material.regularMaterial.opacity(0.68))
            }
        }
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
#else
        if translucentWindow {
            return AnyShapeStyle(Material.ultraThinMaterial)
        }
        return AnyShapeStyle(Color(uiColor: .systemBackground))
#endif
    }

    private var headerBackgroundStyle: AnyShapeStyle {
        if translucentWindow {
            return AnyShapeStyle(Material.ultraThinMaterial.opacity(0.78))
        }
        return AnyShapeStyle(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
    }

    private var rowContainerBackground: AnyShapeStyle {
        if translucentWindow {
            return AnyShapeStyle(Material.ultraThinMaterial.opacity(0.58))
        }
        return AnyShapeStyle(colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.72))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            diffBody
            footerContent
        }
        .frame(minWidth: contentMinWidth, minHeight: contentMinHeight)
        .background(surfaceBackgroundStyle)
#if os(macOS)
        .presentationBackground(surfaceBackgroundStyle)
#endif
        .presentationCornerRadius(28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), comparing \(leftTitle) with \(rightTitle)")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(headerTitleFont)
                        .lineLimit(usesCompactHeader ? 1 : 2)
                        .minimumScaleFactor(0.82)
                    Text(currentHunkLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(currentHunkLabel)
                }
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    Button {
                        moveHunk(by: -1)
                    } label: {
                        Label("Previous Change", systemImage: "chevron.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(headerActionFont)
                    .disabled(diff.hunks.isEmpty)
                    .keyboardShortcut(.upArrow, modifiers: [.command])
                    Button {
                        moveHunk(by: 1)
                    } label: {
                        Label("Next Change", systemImage: "chevron.down")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(headerActionFont)
                    .disabled(diff.hunks.isEmpty)
                    .keyboardShortcut(.downArrow, modifiers: [.command])
                }
            }

            HStack(spacing: 10) {
                SourceBadge(title: leftTitle, symbolName: "doc.text", compact: usesCompactHeader)
                Image(systemName: "arrow.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SourceBadge(title: rightTitle, symbolName: "internaldrive", compact: usesCompactHeader)
            }
        }
        .padding(.horizontal, headerHorizontalPadding)
        .padding(.vertical, headerVerticalPadding)
        .background(headerBackgroundStyle)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var diffBody: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(spacing: 0) {
                    ForEach(diff.rows) { row in
                        DiffRowView(row: row, columnWidth: columnWidth)
                            .id(row.id)
                    }
                }
                .padding(10)
                .background(rowContainerBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                }
                .padding(16)
            }
            .background(surfaceBackgroundStyle)
            .onChange(of: selectedHunkIndex) { _, index in
                guard diff.hunks.indices.contains(index) else { return }
                withAnimation(.easeInOut(duration: 0.18)) {
                    proxy.scrollTo(diff.hunks[index].startRowID, anchor: .top)
                }
            }
            .accessibilityLabel("Diff rows")
            .accessibilityHint("Use Previous Change and Next Change to move through changed regions.")
        }
    }

    @ViewBuilder
    private var footerContent: some View {
        Divider()
        HStack(spacing: 12) {
            if Footer.self != EmptyView.self {
                footer()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
            Button("Close", action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(headerBackgroundStyle)
    }

    private func moveHunk(by offset: Int) {
        guard !diff.hunks.isEmpty else { return }
        selectedHunkIndex = min(max(selectedHunkIndex + offset, 0), diff.hunks.count - 1)
    }
}

private struct SourceBadge: View {
    let title: String
    let symbolName: String
    let compact: Bool

    var body: some View {
        Label {
            Text(title)
                .font((compact ? Font.footnote : Font.callout).weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 5 : 7)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(title)
    }
}

struct CompareTabsPickerView: View {
    let tabs: [TabData]
    let backgroundStyle: AnyShapeStyle
    let onSelect: (UUID) -> Void
    let onCancel: () -> Void
#if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    private var hasComparableTabs: Bool {
        !tabs.isEmpty
    }

    private var contentMinWidth: CGFloat {
#if os(macOS)
        640
#else
        horizontalSizeClass == .compact ? 0 : 640
#endif
    }

    private var contentMinHeight: CGFloat {
#if os(macOS)
        360
#else
        horizontalSizeClass == .compact ? 300 : 360
#endif
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compare with Tab")
                        .font(.title3.weight(.semibold))
                    Text(hasComparableTabs ? "Choose another open tab." : "Open another tab first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 16)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(backgroundStyle)
            .overlay(alignment: .bottom) {
                Divider()
            }

            if hasComparableTabs {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(tabs) { tab in
                            Button {
                                onSelect(tab.id)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(tab.name)
                                            .font(.body.weight(.medium))
                                        if let path = tab.fileURL?.path {
                                            Text(path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        } else {
                                            Text("Unsaved tab")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 12)
                                    Image(systemName: "arrow.left.and.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Compare with \(tab.name)")
                        }
                    }
                    .padding(20)
                }
                .background(backgroundStyle)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No other open tabs")
                        .font(.headline)
                    Text("Compare with Tab compares the current tab against a second tab that is already open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .background(backgroundStyle)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No other open tabs. Compare with Tab compares the current tab against a second tab that is already open.")
            }
        }
        .frame(minWidth: contentMinWidth, minHeight: contentMinHeight)
        .background(backgroundStyle)
    }
}

private struct DiffRowView: View {
    let row: DocumentDiff.Row
    let columnWidth: CGFloat

    private var background: AnyShapeStyle {
        switch row.kind {
        case .equal:
            return AnyShapeStyle(Color.clear)
        case .removed:
            return AnyShapeStyle(Color.red.opacity(0.13))
        case .inserted:
            return AnyShapeStyle(Color.green.opacity(0.13))
        case .changed:
            return AnyShapeStyle(Color.orange.opacity(0.16))
        }
    }

    private var leftIndicatorColor: Color? {
        switch row.kind {
        case .removed, .changed:
            return .red
        case .equal, .inserted:
            return nil
        }
    }

    private var rightIndicatorColor: Color? {
        switch row.kind {
        case .inserted, .changed:
            return .green
        case .equal, .removed:
            return nil
        }
    }

    private var accessibilityLabel: String {
        let leftLine = row.leftLineNumber.map { "left line \($0)" } ?? "no left line"
        let rightLine = row.rightLineNumber.map { "right line \($0)" } ?? "no right line"
        let kind: String
        switch row.kind {
        case .equal: kind = "unchanged"
        case .removed: kind = "removed"
        case .inserted: kind = "inserted"
        case .changed: kind = "changed"
        }
        return "\(kind), \(leftLine), \(rightLine)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            DiffLineCell(
                lineNumber: row.leftLineNumber,
                text: row.leftText,
                width: columnWidth,
                indicatorColor: leftIndicatorColor
            )
            Divider()
            DiffLineCell(
                lineNumber: row.rightLineNumber,
                text: row.rightText,
                width: columnWidth,
                indicatorColor: rightIndicatorColor
            )
        }
        .frame(minWidth: columnWidth * 2, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: row.isChanged ? 6 : 0, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DiffLineCell: View {
    let lineNumber: Int?
    let text: String
    let width: CGFloat
    let indicatorColor: Color?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(indicatorColor ?? .clear)
                .frame(width: 4)
                .padding(.vertical, 1)
                .accessibilityHidden(true)
            Text(lineNumber.map(String.init) ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
            Text(text.isEmpty ? " " : text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
    }
}

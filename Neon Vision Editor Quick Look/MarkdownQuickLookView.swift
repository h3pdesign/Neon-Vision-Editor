//
//  MarkdownQuickLookView.swift
//  Neon Vision Editor Quick Look
//
//  Native, lightweight Markdown document preview for Quick Look.
//

import SwiftUI

struct MarkdownQuickLookView: View {
    let model: PreviewModel
    let theme: EditorTheme

    @State private var showsTableOfContents = false
    @State private var showsSource = false

    private var document: MarkdownQuickLookDocument {
        MarkdownQuickLookDocument(source: model.text)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsSource {
                EditorView(
                    text: model.text,
                    contentType: model.contentType,
                    fileExtension: model.fileExtension,
                    theme: theme,
                    isTruncated: model.isTruncated
                )
            } else {
                documentView
            }

            controls
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Keep the document legible over Finder while retaining the native
        // translucent Quick Look glass treatment.
        .background(.thinMaterial)
    }

    private var documentView: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                if showsTableOfContents, !document.headings.isEmpty {
                    tableOfContents(proxy: proxy)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(document.blocks) { block in
                            MarkdownQuickLookBlockView(block: block)
                                .id(block.id)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 58)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }
                .scrollIndicators(.automatic)
            }
            .animation(.easeInOut(duration: 0.18), value: showsTableOfContents)
        }
    }

    private var controls: some View {
        HStack(spacing: 3) {
            Button {
                showsSource = false
            } label: {
                Image(systemName: "eye")
            }
            .accessibilityLabel("Show rendered Markdown preview")
            .accessibilityAddTraits(showsSource ? [] : .isSelected)
            .quickLookControl(isActive: !showsSource)

            Button {
                showsSource = true
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
            }
            .accessibilityLabel("Show Markdown source")
            .accessibilityAddTraits(showsSource ? .isSelected : [])
            .quickLookControl(isActive: showsSource)

            if !showsSource, !document.headings.isEmpty {
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                Button {
                    showsTableOfContents.toggle()
                } label: {
                    Image(systemName: "list.bullet.indent")
                }
                .accessibilityLabel(showsTableOfContents ? "Hide table of contents" : "Show table of contents")
                .quickLookControl(isActive: showsTableOfContents)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.10))
        }
        .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
    }

    private func tableOfContents(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("Contents")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)

                ForEach(document.headings) { heading in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(heading.id, anchor: .top)
                        }
                    } label: {
                        Text(heading.title)
                            .font(.system(size: 10, weight: heading.level <= 2 ? .semibold : .regular))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(max(0, heading.level - 1)) * 8)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to \(heading.title)")
                }
            }
            .padding(12)
        }
        .frame(width: 210)
        .background(.regularMaterial)
        .overlay(alignment: .trailing) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Markdown table of contents")
    }
}

private extension View {
    func quickLookControl(isActive: Bool) -> some View {
        font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isActive ? Color.accentColor : Color.primary)
            .frame(width: 26, height: 24)
            .background(isActive ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct MarkdownQuickLookBlockView: View {
    let block: MarkdownQuickLookDocument.Block

    var body: some View {
        switch block.kind {
        case let .heading(level, title):
            Text(markdownAttributed(title))
                .font(headingFont(for: level))
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .padding(.top, level == 1 ? 4 : 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .body(source):
            Text(markdownAttributed(source))
                .font(.system(size: 10))
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return .system(size: 21, weight: .bold)
        case 2: return .system(size: 17, weight: .bold)
        case 3: return .system(size: 14, weight: .bold)
        default: return .system(size: 12, weight: .semibold)
        }
    }

    private func markdownAttributed(_ source: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
    }
}

private struct MarkdownQuickLookDocument {
    struct Heading: Identifiable {
        let id: String
        let level: Int
        let title: String
    }

    struct Block: Identifiable {
        enum Kind {
            case heading(level: Int, title: String)
            case body(String)
        }

        let id: String
        let kind: Kind
    }

    let blocks: [Block]
    let headings: [Heading]

    init(source: String) {
        let lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var parsedBlocks: [Block] = []
        var parsedHeadings: [Heading] = []
        var bodyLines: [String] = []

        func flushBody(before index: Int) {
            let body = bodyLines.joined(separator: "\n")
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                bodyLines.removeAll(keepingCapacity: true)
                return
            }
            parsedBlocks.append(Block(id: "body-\(index)", kind: .body(body)))
            bodyLines.removeAll(keepingCapacity: true)
        }

        for (index, line) in lines.enumerated() {
            guard let heading = Self.heading(in: line) else {
                bodyLines.append(line)
                continue
            }

            flushBody(before: index)
            let id = "heading-\(index)"
            parsedHeadings.append(Heading(id: id, level: heading.level, title: heading.title))
            parsedBlocks.append(Block(id: id, kind: .heading(level: heading.level, title: heading.title)))
        }
        flushBody(before: lines.count)

        if parsedBlocks.isEmpty {
            parsedBlocks = [Block(id: "body-empty", kind: .body(source))]
        }
        blocks = parsedBlocks
        headings = parsedHeadings
    }

    private static func heading(in line: String) -> (level: Int, title: String)? {
        let hashes = line.prefix { $0 == "#" }
        let level = hashes.count
        guard (1...6).contains(level) else { return nil }

        let afterHashes = line.dropFirst(level)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }
        let title = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return (level, title)
    }
}

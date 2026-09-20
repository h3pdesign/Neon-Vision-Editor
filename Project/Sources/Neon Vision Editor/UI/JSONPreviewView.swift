import SwiftUI

#Preview("Structured JSON") {
    JSONPreviewView(revision: "sample") {
        #"{"project":"Neon Vision Editor","version":1.8,"active":true,"tags":["Swift","JSON"],"optional":null}"#
    }
    .frame(minWidth: 300, minHeight: 400)
}

struct JSONPreviewView: View {
    let revision: String
    let source: @MainActor () throws -> String
    @Environment(\.colorScheme) private var colorScheme
    @State private var document: JSONPreviewDocument?
    @State private var errorMessage: String?
    @State private var expanded: Set<Int> = [0]
    @State private var pages: [Int: Int] = [:]
    @State private var rows: [JSONPreviewDocument.Row] = []

    var body: some View {
        VStack(spacing: 0) {
            if let document {
                HStack {
                    Label("JSON", systemImage: "curlybraces")
                        .font(.headline)
                    Spacer()
                    Button("Collapse All") {
                        expanded = []
                        rebuildRows(document)
                    }
                }
                .padding(12)
                List(rows) { row in
                    let node = document.nodes[row.nodeID]
                    Group {
                        if row.isPager {
                            pageControls(row, document: document)
                        } else if !node.children.isEmpty {
                            Button {
                                if !expanded.insert(row.nodeID).inserted { expanded.remove(row.nodeID) }
                                rebuildRows(document)
                            } label: {
                                nodeLabel(node, depth: row.depth, expanded: expanded.contains(row.nodeID))
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(expanded.contains(row.nodeID) ? "Expanded" : "Collapsed")
                            .accessibilityHint("Expand or collapse this JSON container")
                        } else {
                            nodeLabel(node, depth: row.depth, expanded: nil)
                        }
                    }
                    .padding(.leading, CGFloat(min(row.depth, 8)) * 12)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                Text(rows.count >= 2_000
                     ? "Visible row limit reached. Collapse branches to explore more."
                     : "100 children per page. Long keys and values are abbreviated; source is unchanged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("JSON Preview Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ProgressView("Parsing JSON…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: revision) {
            document = nil
            errorMessage = nil
            rows = []
            do {
                try await Task.sleep(for: .milliseconds(180))
                let snapshot = try source()
                let worker = Task.detached(priority: .userInitiated) {
                    try JSONPreviewDocument.parse(snapshot)
                }
                let parsed = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                expanded = [0]
                pages = [:]
                document = parsed
                rebuildRows(parsed)
            } catch is CancellationError {
                // Dismissal and newer document revisions cancel stale work.
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func rebuildRows(_ document: JSONPreviewDocument) {
        rows = document.rows(expanded: expanded, pages: pages)
    }

    private func pageControls(_ row: JSONPreviewDocument.Row, document: JSONPreviewDocument) -> some View {
        let page = pages[row.nodeID, default: 0]
        let count = document.nodes[row.nodeID].children.count
        return HStack {
            Button("Previous") {
                pages[row.nodeID] = page - 1
                rebuildRows(document)
            }
            .disabled(page == 0)
            Text("\(page * 100 + 1)–\(min((page + 1) * 100, count)) of \(count)")
                .font(.caption.monospacedDigit())
            Button("Next") {
                pages[row.nodeID] = page + 1
                rebuildRows(document)
            }
            .disabled((page + 1) * 100 >= count)
        }
        .buttonStyle(.borderless)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Children of \(document.nodes[row.nodeID].name)")
    }

    private func nodeLabel(_ node: JSONPreviewDocument.Node, depth: Int, expanded: Bool?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: expanded.map { $0 ? "chevron.down" : "chevron.right" } ?? "minus")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: node.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.cyan : Color(red: 0.10, green: 0.30, blue: 0.65))
                    .lineLimit(2)
                Text(verbatim: node.value)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(valueColor(node.kind))
                    .lineLimit(3)
                Text(node.kind.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(node.name), \(node.kind.rawValue), \(node.value), level \(depth + 1)")
    }

    private func valueColor(_ kind: JSONPreviewDocument.Kind) -> Color {
        let dark = colorScheme == .dark
        switch kind {
        case .string: return dark ? Color(red: 0.48, green: 0.85, blue: 0.66) : Color(red: 0.0, green: 0.38, blue: 0.22)
        case .number: return dark ? Color(red: 0.80, green: 0.67, blue: 1) : Color(red: 0.43, green: 0.20, blue: 0.65)
        case .boolean: return dark ? Color(red: 1, green: 0.76, blue: 0.44) : Color(red: 0.58, green: 0.29, blue: 0.02)
        case .null: return .secondary
        case .object, .array: return .primary
        }
    }
}

extension ContentView {
    var jsonPreviewPane: some View {
        VStack(spacing: 0) {
            previewPaneHeader(title: "JSON Preview", iconName: "curlybraces", metadata: nil, onClose: closeCurrentPreview) {
                EmptyView()
            }
            if let tab = viewModel.selectedTab {
                JSONPreviewView(revision: "\(tab.contentRevision)-\(tab.isLoadingContent)") {
                    guard !tab.isLoadingContent else {
                        throw JSONPreviewDocument.Failure(message: "The document is still loading.")
                    }
                    // Never materialize a URL-backed excessive document on the UI thread.
                    guard !tab.usesFileBackedStorage, tab.document.utf16Length <= JSONPreviewDocument.maximumBytes else {
                        throw JSONPreviewDocument.Failure(message: "This document exceeds the structured preview limit. The source remains available in the editor.")
                    }
                    return tab.document.string()
                }
                .id(tab.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorSurfaceBackgroundStyle)
    }
}

import SwiftUI

struct YAMLPreviewView: View {
    let revision: String
    let source: @MainActor () throws -> String
    @State private var document: YAMLPreviewDocument?
    @State private var page = 0
    @State private var html: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                ContentUnavailableView("YAML Preview Unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if let document {
                HStack {
                    Button("Previous") { page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("Page \(page + 1) of \(document.pages.count)").font(.caption.monospacedDigit())
                    Spacer()
                    Button("Next") { page += 1 }.disabled(page + 1 >= document.pages.count)
                }
                .padding(12)
                if let html {
                    MarkdownPreviewWebView(html: html, baseURL: nil)
                        .id(page)
                } else {
                    ProgressView("Coloring YAML…").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text("Syntax-colored source; not YAML validation. Large files and long lines are paged. Source is unchanged.")
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            } else {
                ProgressView("Preparing YAML…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: revision) {
            document = nil
            html = nil
            errorMessage = nil
            page = 0
            do {
                try await Task.sleep(for: .milliseconds(180))
                let snapshot = try source()
                let worker = Task.detached(priority: .userInitiated) { try YAMLPreviewDocument.prepare(snapshot) }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                document = result
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
        .task(id: "\(revision)-\(document != nil)-\(page)") {
            html = nil
            guard let document, document.pages.indices.contains(page) else { return }
            do {
                let text = document.pages[page]
                let worker = Task.detached(priority: .userInitiated) { try YAMLPreviewDocument.html(for: text) }
                let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                html = result
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
        }
    }
}

extension ContentView {
    var yamlPreviewPane: some View {
        VStack(spacing: 0) {
            previewPaneHeader(title: "YAML Preview", iconName: "doc.text", metadata: nil, onClose: closeCurrentPreview) { EmptyView() }
            if let tab = viewModel.selectedTab {
                YAMLPreviewView(revision: "\(tab.contentRevision)-\(tab.isLoadingContent)") {
                    guard !tab.isLoadingContent else {
                        throw JSONPreviewDocument.Failure(message: "The document is still loading.")
                    }
                    guard !tab.usesFileBackedStorage, tab.document.utf16Length <= YAMLPreviewDocument.maximumBytes else {
                        throw JSONPreviewDocument.Failure(message: "This document exceeds the YAML preview limit. The source remains available in the editor.")
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

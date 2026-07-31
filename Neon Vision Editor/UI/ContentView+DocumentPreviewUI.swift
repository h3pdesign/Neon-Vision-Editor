import SwiftUI
import Foundation
import PDFKit

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Image and PDF Preview UI

extension ContentView {
    @ViewBuilder
    var imagePreviewPane: some View {
        documentPreviewContainer(title: "PNG Preview", iconName: "photo") {
            if let url = viewModel.selectedTab?.fileURL {
                ImagePreviewDocumentView(url: url)
            } else {
                documentPreviewUnavailableView("No PNG file is open.")
            }
        }
    }

    @ViewBuilder
    var pdfPreviewPane: some View {
        documentPreviewContainer(title: "PDF Preview", iconName: "doc.richtext") {
            if let url = pdfPreviewURL {
                PDFAnnotationWorkspaceView(
                    url: url,
                    hasAttachedNoteEditor: pdfNoteTabID != nil,
                    showsNotePreview: isPDFNoteMarkdownPreviewVisible,
                    onOpenNotes: openPDFNotesEditor,
                    onToggleNotePreview: { isPDFNoteMarkdownPreviewVisible.toggle() }
                )
            } else {
                documentPreviewUnavailableView("No PDF file is open.")
            }
        }
    }

    private func documentPreviewContainer<Content: View>(
        title: String,
        iconName: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                Button(action: closeCurrentPreview) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                Rectangle()
                    .fill(documentPreviewHeaderBackgroundColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(editorSurfaceBackgroundStyle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func documentPreviewUnavailableView(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentPreviewHeaderBackgroundColor: Color {
#if os(macOS)
        currentEditorTheme(colorScheme: colorScheme).background
#else
        Color(.systemBackground)
#endif
    }
}

private struct ImagePreviewDocumentView: View {
    let url: URL
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let imageData, let image = platformImage(data: imageData) {
                image
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .accessibilityLabel("PNG image")
            } else if imageData != nil {
                Text("Unable to decode this PNG file.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Loading PNG…")
            }
        }
        .task(id: url) {
            imageData = try? await Task.detached(priority: .userInitiated) {
                try Data(contentsOf: url)
            }.value
        }
    }
}

private struct PDFPreviewDocumentView: View {
    let url: URL

    var body: some View {
        NativePDFView(url: url)
            .accessibilityLabel("PDF document")
    }
}

#if os(macOS)
private func platformImage(data: Data) -> Image? {
    guard let image = NSImage(data: data) else { return nil }
    return Image(nsImage: image)
}

private struct NativePDFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        configure(view)
    }

    private func configure(_ view: PDFView) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.windowBackgroundColor
    }
}
#elseif canImport(UIKit)
private func platformImage(data: Data) -> Image? {
    guard let image = UIImage(data: data) else { return nil }
    return Image(uiImage: image)
}

private struct NativePDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        configure(view)
    }

    private func configure(_ view: PDFView) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = UIColor.systemBackground
    }
}
#endif

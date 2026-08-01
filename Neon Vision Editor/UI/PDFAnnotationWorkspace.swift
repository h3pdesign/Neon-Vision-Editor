import SwiftUI
import Foundation
import PDFKit

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct PDFAnnotationWorkspaceView: View {
    let url: URL
    let hasAttachedNoteEditor: Bool
    let showsNotePreview: Bool
    let onOpenNotes: () -> Void
    let onToggleNotePreview: () -> Void
    let onHighlightSaved: (String) -> Void

    @State private var highlightTrigger = 0
    @State private var canHighlight = false

    var body: some View {
        VStack(spacing: 0) {
            header
            pdfView
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PDF preview and annotations")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            Button {
                highlightTrigger += 1
            } label: {
                Label("Highlight", systemImage: "highlighter")
            }
            .buttonStyle(.borderless)
            .disabled(!canHighlight)
            .help("Highlight the current PDF selection")
            .accessibilityHint("Select text in the PDF first")
            Button {
                onOpenNotes()
            } label: {
                Label("Notes", systemImage: hasAttachedNoteEditor ? "note.text" : "note")
            }
            .buttonStyle(.borderless)
            .accessibilityValue(hasAttachedNoteEditor ? "Editor open" : "Editor closed")
            if hasAttachedNoteEditor {
                Button {
                    onToggleNotePreview()
                } label: {
                    Label("Markdown Preview", systemImage: showsNotePreview ? "eye.fill" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityValue(showsNotePreview ? "Shown" : "Hidden")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.secondary.opacity(0.08))
    }

    private var pdfView: some View {
        NativePDFAnnotationView(
            url: url,
            highlightTrigger: highlightTrigger,
            onSelectionChanged: { selectionIsAvailable in
                canHighlight = selectionIsAvailable
            },
            onHighlightSaved: onHighlightSaved
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("PDF document")
    }

}

#if os(macOS)
private struct NativePDFAnnotationView: NSViewRepresentable {
    let url: URL
    let highlightTrigger: Int
    let onSelectionChanged: (Bool) -> Void
    let onHighlightSaved: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        context.coordinator.attach(to: view)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        configure(view, coordinator: context.coordinator)
        if context.coordinator.lastHighlightTrigger != highlightTrigger {
            context.coordinator.lastHighlightTrigger = highlightTrigger
            context.coordinator.highlightSelection(in: view)
        }
    }

    private func configure(_ view: PDFView, coordinator: Coordinator) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            coordinator.loadStoredHighlights(in: view, url: url)
        }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .windowBackgroundColor
    }

    final class Coordinator: NSObject {
        var parent: NativePDFAnnotationView
        var lastHighlightTrigger = 0
        private weak var view: PDFView?
        private var loadedIDs = Set<UUID>()

        init(_ parent: NativePDFAnnotationView) { self.parent = parent }

        func attach(to view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged),
                name: Notification.Name.PDFViewSelectionChanged,
                object: view
            )
        }

        @objc private func selectionChanged() {
            let selectionIsAvailable = !(view?.currentSelection?.string?.isEmpty ?? true)
            // PDFKit can deliver selection notifications while SwiftUI is
            // reconciling the representable. Defer the binding update until
            // that reconciliation has finished.
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChanged(selectionIsAvailable)
            }
        }

        func loadStoredHighlights(in view: PDFView, url: URL) {
            Task {
                let records = await PDFAnnotationStore.shared.highlights(for: url)
                await MainActor.run {
                    for record in records { self.add(record, to: view) }
                }
            }
        }

        func highlightSelection(in view: PDFView) {
            guard let selection = view.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let document = view.document else { return }
            for page in selection.pages {
                let pageBounds = page.bounds(for: .cropBox)
                let rect = selection.bounds(for: page).intersection(pageBounds)
                guard rect.width > 1, rect.height > 1, pageBounds.width > 0, pageBounds.height > 0 else { continue }
                let record = PDFHighlightRecord(
                    id: UUID(),
                    pageIndex: document.index(for: page),
                    normalizedRect: PDFNormalizedRect(
                        x: Double((rect.minX - pageBounds.minX) / pageBounds.width),
                        y: Double((rect.minY - pageBounds.minY) / pageBounds.height),
                        width: Double(rect.width / pageBounds.width),
                        height: Double(rect.height / pageBounds.height)
                    ),
                    selectedText: text,
                    createdAt: Date()
                )
                add(record, to: view)
                Task { await PDFAnnotationStore.shared.add(record, for: parent.url) }
            }
            // This method is called from updateNSView/updateUIView when the
            // toolbar trigger changes. Defer both callbacks so their SwiftUI
            // state mutations do not occur during view reconciliation.
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChanged(false)
                self?.parent.onHighlightSaved(text)
            }
            view.clearSelection()
        }

        private func add(_ record: PDFHighlightRecord, to view: PDFView) {
            guard !loadedIDs.contains(record.id),
                  let page = view.document?.page(at: record.pageIndex) else { return }
            let bounds = page.bounds(for: .cropBox)
            let rect = CGRect(
                x: bounds.minX + CGFloat(record.normalizedRect.x) * bounds.width,
                y: bounds.minY + CGFloat(record.normalizedRect.y) * bounds.height,
                width: CGFloat(record.normalizedRect.width) * bounds.width,
                height: CGFloat(record.normalizedRect.height) * bounds.height
            )
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.contents = record.selectedText
            page.addAnnotation(annotation)
            loadedIDs.insert(record.id)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
#elseif canImport(UIKit)
private struct NativePDFAnnotationView: UIViewRepresentable {
    let url: URL
    let highlightTrigger: Int
    let onSelectionChanged: (Bool) -> Void
    let onHighlightSaved: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        context.coordinator.attach(to: view)
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        context.coordinator.parent = self
        configure(view, coordinator: context.coordinator)
        if context.coordinator.lastHighlightTrigger != highlightTrigger {
            context.coordinator.lastHighlightTrigger = highlightTrigger
            context.coordinator.highlightSelection(in: view)
        }
    }

    private func configure(_ view: PDFView, coordinator: Coordinator) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
            coordinator.loadStoredHighlights(in: view, url: url)
        }
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground
    }

    final class Coordinator: NSObject {
        var parent: NativePDFAnnotationView
        var lastHighlightTrigger = 0
        private weak var view: PDFView?
        private var loadedIDs = Set<UUID>()

        init(_ parent: NativePDFAnnotationView) { self.parent = parent }

        func attach(to view: PDFView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(selectionChanged),
                name: Notification.Name.PDFViewSelectionChanged,
                object: view
            )
        }

        @objc private func selectionChanged() {
            let selectionIsAvailable = !(view?.currentSelection?.string?.isEmpty ?? true)
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChanged(selectionIsAvailable)
            }
        }

        func loadStoredHighlights(in view: PDFView, url: URL) {
            Task {
                let records = await PDFAnnotationStore.shared.highlights(for: url)
                await MainActor.run {
                    for record in records { self.add(record, to: view) }
                }
            }
        }

        func highlightSelection(in view: PDFView) {
            guard let selection = view.currentSelection,
                  let text = selection.string,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let document = view.document else { return }
            for page in selection.pages {
                let pageBounds = page.bounds(for: .cropBox)
                let rect = selection.bounds(for: page).intersection(pageBounds)
                guard rect.width > 1, rect.height > 1, pageBounds.width > 0, pageBounds.height > 0 else { continue }
                let record = PDFHighlightRecord(
                    id: UUID(),
                    pageIndex: document.index(for: page),
                    normalizedRect: PDFNormalizedRect(
                        x: Double((rect.minX - pageBounds.minX) / pageBounds.width),
                        y: Double((rect.minY - pageBounds.minY) / pageBounds.height),
                        width: Double(rect.width / pageBounds.width),
                        height: Double(rect.height / pageBounds.height)
                    ),
                    selectedText: text,
                    createdAt: Date()
                )
                add(record, to: view)
                Task { await PDFAnnotationStore.shared.add(record, for: parent.url) }
            }
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChanged(false)
                self?.parent.onHighlightSaved(text)
            }
            view.clearSelection()
        }

        private func add(_ record: PDFHighlightRecord, to view: PDFView) {
            guard !loadedIDs.contains(record.id),
                  let page = view.document?.page(at: record.pageIndex) else { return }
            let bounds = page.bounds(for: .cropBox)
            let rect = CGRect(
                x: bounds.minX + CGFloat(record.normalizedRect.x) * bounds.width,
                y: bounds.minY + CGFloat(record.normalizedRect.y) * bounds.height,
                width: CGFloat(record.normalizedRect.width) * bounds.width,
                height: CGFloat(record.normalizedRect.height) * bounds.height
            )
            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.contents = record.selectedText
            page.addAnnotation(annotation)
            loadedIDs.insert(record.id)
        }

        deinit { NotificationCenter.default.removeObserver(self) }
    }
}
#endif

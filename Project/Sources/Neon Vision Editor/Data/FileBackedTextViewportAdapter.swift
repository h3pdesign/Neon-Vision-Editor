import Foundation

/// Bridges a bounded native text viewport to the backend-neutral document contract.
final class FileBackedTextViewportAdapter {
    let document: any EditorDocument
    let maximumByteCount: Int

    init(document: any EditorDocument, maximumByteCount: Int = 256_000) {
        self.document = document
        self.maximumByteCount = max(1, maximumByteCount)
    }

    func window(aroundLine line: Int) throws -> EditorDocumentViewport {
        try document.viewport(aroundLine: line, maximumByteCount: maximumByteCount)
    }

    func replace(
        in viewport: EditorDocumentViewport,
        utf16Range: NSRange,
        with replacement: String
    ) throws {
        try document.replace(in: viewport, utf16Range: utf16Range, with: replacement)
    }
}

import Foundation
import CryptoKit

nonisolated struct PDFHighlightRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let pageIndex: Int
    let normalizedRect: PDFNormalizedRect
    let selectedText: String
    let createdAt: Date
}

nonisolated struct PDFNormalizedRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct PDFAnnotationDocument: Codable, Sendable {
    var version: Int = 1
    var highlights: [PDFHighlightRecord] = []
}

/// Small, app-owned sidecar store. PDFs are intentionally never rewritten for a highlight.
actor PDFAnnotationStore {
    static let shared = PDFAnnotationStore()

    private var cache: [String: PDFAnnotationDocument] = [:]

    func highlights(for pdfURL: URL) -> [PDFHighlightRecord] {
        let key = Self.key(for: pdfURL)
        if let cached = cache[key] { return cached.highlights }
        let document = Self.readDocument(for: key)
        cache[key] = document
        return document.highlights
    }

    func add(_ record: PDFHighlightRecord, for pdfURL: URL) {
        let key = Self.key(for: pdfURL)
        var document = cache[key] ?? Self.readDocument(for: key)
        guard !document.highlights.contains(where: { $0.id == record.id }) else { return }
        document.highlights.append(record)
        cache[key] = document
        Self.write(document, for: key)
    }

    private static func key(for url: URL) -> String {
        let standardized = url.standardizedFileURL.path
        // Keep the key stable across normal PDF saves. Position/text records remain
        // useful when the document metadata changes, without hashing the PDF on open.
        return SHA256.hash(data: Data(standardized.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func storeDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Neon Vision Editor", isDirectory: true)
            .appendingPathComponent("PDFAnnotations", isDirectory: true)
    }

    private static func fileURL(for key: String) -> URL {
        storeDirectory().appendingPathComponent("\(key).json")
    }

    private static func readDocument(for key: String) -> PDFAnnotationDocument {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let document = try? JSONDecoder().decode(PDFAnnotationDocument.self, from: data) else {
            return PDFAnnotationDocument()
        }
        return document
    }

    private static func write(_ document: PDFAnnotationDocument, for key: String) {
        let directory = storeDirectory()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(document)
            try data.write(to: fileURL(for: key), options: .atomic)
        } catch {
            // Annotation persistence is best effort and must never interrupt PDF scrolling.
        }
    }
}

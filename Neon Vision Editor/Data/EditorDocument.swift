import Foundation

/// Backend-neutral document contract shared by the editor state and persistence.
///
/// The compatibility `string()` API exists for small-document/TextKit features.
/// Large-document code must use a bounded window provider instead of requesting
/// the entire string.
enum EditorDocumentStorageKind: Sendable {
    case inMemory
    case fileBacked
}

struct EditorDocumentViewport: Equatable {
    let text: String
    let startByteOffset: Int
    let startUTF16Offset: Int
    let lineRange: ClosedRange<Int>
    let generation: UInt64
}

protocol EditorDocument: AnyObject {
    var storageKind: EditorDocumentStorageKind { get }
    var utf16Length: Int { get }
    var isDirty: Bool { get }
    var supportsBoundedWindows: Bool { get }
    var lineCount: Int { get }

    func string() -> String
    func replace(range: NSRange, with replacement: String) throws
    /// Applies a native UTF-16 edit without exposing the document's storage.
    /// Large live editors use the viewport overload below; this is the
    /// backend-neutral fallback for non-viewport commands.
    func replace(utf16Range: NSRange, with replacement: String) throws
    func replaceAll(with text: String) throws
    func markClean()
    func viewport(aroundLine line: Int, maximumByteCount: Int) throws -> EditorDocumentViewport
    func replace(in viewport: EditorDocumentViewport, utf16Range: NSRange, with replacement: String) throws
}

extension EditorDocument {
    var supportsBoundedWindows: Bool { true }
    var lineCount: Int { 1 }
}

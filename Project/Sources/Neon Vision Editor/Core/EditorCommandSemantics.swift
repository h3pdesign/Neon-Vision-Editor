import Foundation

/// Backend-neutral semantics shared by native editor surfaces.
enum EditorCommandSemantics {
    /// Untargeted legacy events retain their existing routing. A targeted event
    /// belongs only to the model containing that document, never its neighbours.
    static func acceptsDocumentEvent(documentID: String?, openDocumentIDs: [UUID]) -> Bool {
        guard let documentID else { return true }
        guard let id = UUID(uuidString: documentID) else { return false }
        return openDocumentIDs.contains(id)
    }

    static func indentation(style: String, width: Int) -> String {
        style == "tabs" ? "\t" : String(repeating: " ", count: max(1, width))
    }

    static func markdownCommand(for input: String?) -> String? {
        switch input?.lowercased() {
        case "b": "bold"
        case "i": "italic"
        case "k": "link"
        default: nil
        }
    }
}

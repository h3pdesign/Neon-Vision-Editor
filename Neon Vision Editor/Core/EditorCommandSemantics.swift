import Foundation

/// Backend-neutral semantics shared by native editor surfaces.
enum EditorCommandSemantics {
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

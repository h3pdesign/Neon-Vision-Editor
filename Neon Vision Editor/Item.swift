import Foundation
import SwiftData

@Model
final class Tab {
    var id: UUID = UUID()
    var name: String
    var content: String
    var language: String
    var isModified: Bool

    init(name: String = "Untitled", content: String = "", language: String = "swift") {
        self.name = name
        self.content = content
        self.language = language
        self.isModified = false
    }
}

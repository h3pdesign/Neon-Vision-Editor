import Foundation
import SwiftData

// MARK: - Tab
@Model
class Tab {
    var id: UUID = UUID()
    var name: String
    var content: String
    var language: String
    
    init(name: String = "Note", content: String = "", language: String = "swift") {
        self.name = name
        self.content = content
        self.language = language
    }
}
import SwiftData
import Foundation // Added to provide UUID type

@Model
class Item: Identifiable {
    var id = UUID() // Unique identifier for Identifiable conformance
    var name: String
    var content: String
    var language: String
    
    init(name: String, content: String, language: String) {
        self.name = name
        self.content = content
        self.language = language
    }
}

import Foundation
import SwiftUI
import Combine

/// Log entry representing a single log message
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .debug: return .secondary
            case .info: return .primary
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
}

/// Observable logger that maintains a list of log entries
@MainActor
class AppLogger: ObservableObject {
    static let shared = AppLogger()
    
    @Published private(set) var entries: [LogEntry] = []
    @Published var maxEntries: Int = 1000
    @Published var filterLevel: LogEntry.LogLevel? = nil
    @Published var filterCategory: String? = nil
    
    private init() {}
    
    /// Log a message with a specific level and category
    nonisolated func log(_ message: String, level: LogEntry.LogLevel = .info, category: String = "General") {
        let entry = LogEntry(timestamp: Date(), level: level, category: category, message: message)
        
        // Dispatch to main actor for UI updates
        Task { @MainActor in
            entries.append(entry)
            
            // Trim to max entries
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
        
        // Also print to console in debug builds (synchronously)
        #if DEBUG
        print("[\(level.rawValue)][\(category)] \(message)")
        #endif
    }
    
    /// Convenience methods
    nonisolated func debug(_ message: String, category: String = "General") {
        log(message, level: .debug, category: category)
    }
    
    nonisolated func info(_ message: String, category: String = "General") {
        log(message, level: .info, category: category)
    }
    
    nonisolated func warning(_ message: String, category: String = "General") {
        log(message, level: .warning, category: category)
    }
    
    nonisolated func error(_ message: String, category: String = "General") {
        log(message, level: .error, category: category)
    }
    
    /// Clear all log entries
    func clear() {
        entries.removeAll()
    }
    
    /// Get filtered entries based on current filters
    var filteredEntries: [LogEntry] {
        var result = entries
        
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }
        
        if let category = filterCategory, !category.isEmpty {
            result = result.filter { $0.category.localizedCaseInsensitiveContains(category) }
        }
        
        return result
    }
    
    /// Get unique categories
    var categories: [String] {
        Array(Set(entries.map { $0.category })).sorted()
    }
}

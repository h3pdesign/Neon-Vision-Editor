import Foundation
import Observation

@MainActor
@Observable


// MARK: - Types

final class AIActivityLog {
    enum Level: String, CaseIterable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    struct Entry: Identifiable, Equatable {
        let id = UUID()
        let timestamp: Date
        let level: Level
        let source: String
        let message: String
    }

    static let shared = AIActivityLog()
    private static let maxEntries = 500

    private(set) var entries: [Entry] = []

    private init() {}

    func append(_ message: String, level: Level = .info, source: String = "AI") {
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSource = trimmedSource.isEmpty ? "AI" : trimmedSource
        let normalizedMessage = Self.redactedMessage(message.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !normalizedMessage.isEmpty else { return }
        entries.append(
            Entry(
                timestamp: Date(),
                level: level,
                source: normalizedSource,
                message: normalizedMessage
            )
        )
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    nonisolated static func record(_ message: String, level: Level = .info, source: String = "AI") {
        Task { @MainActor in
            shared.append(message, level: level, source: source)
        }
    }

    private static func redactedMessage(_ message: String) -> String {
        var redacted = message
        let patterns = [
            #"(?i)\b(bearer|token|api[_-]?key)\s*[:=]\s*[A-Za-z0-9._\-]{8,}"#,
            #"\b(sk|xai|AIza|sk-ant)-[A-Za-z0-9._\-]{8,}"#,
            #"/Users/[^\s'"]+"#,
            #"file://[^\s'"]+"#
        ]
        for pattern in patterns {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: "[redacted]",
                options: .regularExpression
            )
        }
        return redacted
    }
}

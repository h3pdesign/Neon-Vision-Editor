import Foundation

struct StructuredLogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let lineNumber: Int
    let timestamp: String?
    let message: String
    let severity: StructuredLogSeverity
}

enum StructuredLogSeverity: String, CaseIterable, Sendable {
    case critical
    case error
    case warning
    case info
    case debug
    case trace
    case other

    var title: String {
        switch self {
        case .critical: return "Critical"
        case .error: return "Errors"
        case .warning: return "Warnings"
        case .info: return "Information"
        case .debug: return "Debug"
        case .trace: return "Trace"
        case .other: return "Other"
        }
    }
}

struct StructuredLogSection: Identifiable, Hashable, Sendable {
    var id: String { severity.rawValue }
    let severity: StructuredLogSeverity
    let entries: [StructuredLogEntry]
}

struct StructuredLogSnapshot: Hashable, Sendable {
    let totalEntries: Int
    let displayedEntries: Int
    let sections: [StructuredLogSection]

    var isTruncated: Bool { displayedEntries < totalEntries }
}

enum StructuredLogParser {
    nonisolated private static let inspectionLimit = 1_000_000
    nonisolated private static let maximumEntries = 600

    nonisolated static func snapshot(from text: String) -> StructuredLogSnapshot {
        let source = String(text.prefix(inspectionLimit))
        let lines = source.components(separatedBy: .newlines)
        let severityPattern = #"\b(FATAL|CRITICAL|FAULT|ERROR|ERR|WARN|WARNING|NOTICE|INFO|DEFAULT|DEBUG|TRACE|VERBOSE)\b"#
        let timestampPattern = #"^\s*(?:\[)?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:[.,]\d+)?(?:Z|[+-]\d{2}:?\d{2})?|[A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})(?:\])?"#
        let severityRegex = try? NSRegularExpression(pattern: severityPattern, options: [.caseInsensitive])
        let timestampRegex = try? NSRegularExpression(pattern: timestampPattern)

        var totalEntries = 0
        var entriesBySeverity: [StructuredLogSeverity: [StructuredLogEntry]] = [:]
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            totalEntries += 1
            guard totalEntries <= maximumEntries else { continue }

            if let jsonEntry = jsonEntry(from: line, lineNumber: index + 1) {
                entriesBySeverity[jsonEntry.severity, default: []].append(jsonEntry)
                continue
            }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let severityMatch = severityRegex?.firstMatch(in: line, range: fullRange)
            let timestampMatch = timestampRegex?.firstMatch(in: line, range: fullRange)
            let severityToken = severityMatch.flatMap { rangeString($0.range, in: line) }
            let timestamp = timestampMatch.flatMap { match -> String? in
                let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                return rangeString(range, in: line)
            }
            let severity = severity(from: severityToken)
            let message = cleanedMessage(line, removing: [timestampMatch?.range, severityMatch?.range].compactMap { $0 })
            let entry = StructuredLogEntry(
                id: "\(index)-\(line.hashValue)",
                lineNumber: index + 1,
                timestamp: timestamp,
                message: message.isEmpty ? line : message,
                severity: severity
            )
            entriesBySeverity[severity, default: []].append(entry)
        }

        let sections = StructuredLogSeverity.allCases.compactMap { severity -> StructuredLogSection? in
            guard let entries = entriesBySeverity[severity], !entries.isEmpty else { return nil }
            return StructuredLogSection(severity: severity, entries: entries)
        }
        return StructuredLogSnapshot(
            totalEntries: totalEntries,
            displayedEntries: min(totalEntries, maximumEntries),
            sections: sections
        )
    }

    nonisolated private static func jsonEntry(from line: String, lineNumber: Int) -> StructuredLogEntry? {
        guard line.first == "{", line.utf8.count <= 64_000,
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return nil
        }
        let level = stringValue(object["level"])
            ?? stringValue(object["severity"])
            ?? stringValue(object["log.level"])
        let message = stringValue(object["message"])
            ?? stringValue(object["msg"])
            ?? stringValue(object["event"])
        guard level != nil || message != nil else { return nil }
        let timestamp = stringValue(object["timestamp"])
            ?? stringValue(object["time"])
            ?? stringValue(object["@timestamp"])
        let severity = severity(from: level)
        return StructuredLogEntry(
            id: "json-\(lineNumber)-\(line.hashValue)",
            lineNumber: lineNumber,
            timestamp: timestamp,
            message: message ?? line,
            severity: severity
        )
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }

    nonisolated private static func severity(from token: String?) -> StructuredLogSeverity {
        switch token?.lowercased() {
        case "fatal", "critical", "fault": return .critical
        case "error", "err": return .error
        case "warn", "warning": return .warning
        case "notice", "info", "default": return .info
        case "debug": return .debug
        case "trace", "verbose": return .trace
        default: return .other
        }
    }

    nonisolated private static func rangeString(_ range: NSRange, in text: String) -> String? {
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    nonisolated private static func cleanedMessage(_ line: String, removing ranges: [NSRange]) -> String {
        let mutable = NSMutableString(string: line)
        for range in ranges.sorted(by: { $0.location > $1.location }) where NSMaxRange(range) <= mutable.length {
            mutable.replaceCharacters(in: range, with: "")
        }
        return String(mutable)
            .trimmingCharacters(in: CharacterSet(charactersIn: " []:-\t"))
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }
}

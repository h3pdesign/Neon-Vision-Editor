import Foundation

struct AppleCrashReportEntry: Identifiable, Hashable, Sendable {
    let id: String
    let key: String
    let value: String
    let severity: AppleCrashReportSeverity
}

enum AppleCrashReportSeverity: String, Sendable {
    case critical
    case warning
    case info
}

struct AppleCrashReportSection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let entries: [AppleCrashReportEntry]
}

enum AppleCrashReportParser {
    nonisolated private static let inspectionLimit = 1_000_000
    nonisolated private static let maximumThreadEntries = 80
    nonisolated private static let maximumBinaryImageEntries = 40

    nonisolated static func looksLikeAppleCrashReport(_ text: String) -> Bool {
        let sample = String(text.prefix(16_000)).lowercased()
        let legacyMarkers = [
            "incident identifier:", "exception type:", "termination reason:",
            "crashed thread:", "binary images:", "thread 0 crashed:"
        ]
        if legacyMarkers.filter(sample.contains).count >= 2 {
            return true
        }

        let jsonLines = sample.split(whereSeparator: \.isNewline)
        guard let metadataLine = jsonLines.first(where: { $0.trimmingCharacters(in: .whitespaces).first == "{" }) else { return false }
        if metadataLine.contains("\"bug_type\"") && metadataLine.contains("309") {
            return true
        }
        let jsonMarkers = ["\"incident\"", "\"exception\"", "\"termination\"", "\"threads\"", "\"usedimages\""]
        return jsonMarkers.filter(sample.contains).count >= 3
    }

    nonisolated static func sections(from text: String) -> [AppleCrashReportSection] {
        let source = String(text.prefix(inspectionLimit))
        if let jsonSections = jsonSections(from: source), !jsonSections.isEmpty {
            return jsonSections
        }
        return legacySections(from: source)
    }

    nonisolated private static func legacySections(from text: String) -> [AppleCrashReportSection] {
        let lines = text.components(separatedBy: .newlines)
        var summary: [AppleCrashReportEntry] = []
        var failure: [AppleCrashReportEntry] = []
        let summaryKeys: Set<String> = [
            "process", "path", "identifier", "version", "code type", "parent process",
            "date/time", "os version", "report version", "incident identifier"
        ]
        let failureKeys: Set<String> = [
            "exception type", "exception codes", "exception subtype", "termination reason",
            "termination signal", "crashed thread", "application specific information"
        ]

        for (index, line) in lines.enumerated() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let normalizedKey = key.lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            if summaryKeys.contains(normalizedKey) {
                summary.append(entry(key: key, value: value, severity: .info, index: index))
            } else if failureKeys.contains(normalizedKey) {
                let severity: AppleCrashReportSeverity = normalizedKey == "exception type" || normalizedKey == "termination reason" ? .critical : .warning
                failure.append(entry(key: key, value: value, severity: severity, index: index))
            }
        }

        var sections: [AppleCrashReportSection] = []
        if !summary.isEmpty {
            sections.append(AppleCrashReportSection(id: "summary", title: "Summary", entries: summary))
        }
        if !failure.isEmpty {
            sections.append(AppleCrashReportSection(id: "failure", title: "Crash Cause", entries: failure))
        }

        let threadEntries = legacyThreadEntries(from: lines)
        if !threadEntries.isEmpty {
            sections.append(AppleCrashReportSection(id: "threads", title: "Threads", entries: threadEntries))
        }

        let binaryImageEntries = legacyBinaryImageEntries(from: lines)
        if !binaryImageEntries.isEmpty {
            sections.append(AppleCrashReportSection(id: "images", title: "Binary Images", entries: binaryImageEntries))
        }
        return sections
    }

    nonisolated private static func legacyThreadEntries(from lines: [String]) -> [AppleCrashReportEntry] {
        var entries: [AppleCrashReportEntry] = []
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.range(of: #"^Thread\s+\d+(?:\s+Crashed)?\s*:"#, options: .regularExpression) != nil else { continue }
            let isCrashed = trimmed.localizedCaseInsensitiveContains("crashed")
            entries.append(entry(
                key: isCrashed ? "Crashed thread" : "Thread",
                value: trimmed,
                severity: isCrashed ? .critical : .info,
                index: index
            ))
            if entries.count == maximumThreadEntries { break }
        }
        return entries
    }

    nonisolated private static func legacyBinaryImageEntries(from lines: [String]) -> [AppleCrashReportEntry] {
        guard let headingIndex = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "binary images:" }) else {
            return []
        }
        let imageLines = lines.dropFirst(headingIndex + 1)
            .prefix { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let entries = imageLines.prefix(maximumBinaryImageEntries).enumerated().map { offset, line in
            entry(key: "Image", value: line.trimmingCharacters(in: .whitespaces), severity: .info, index: headingIndex + offset + 1)
        }
        guard !entries.isEmpty else { return [] }
        return [entry(key: "Images", value: "\(imageLines.count) listed", severity: .info, index: headingIndex)] + entries
    }

    nonisolated private static func jsonSections(from text: String) -> [AppleCrashReportSection]? {
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstObject = lines.first.flatMap { line in
            try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        }
        let report: [String: Any]?
        if let firstObject,
           let bugType = stringValue(firstObject["bug_type"]),
           bugType == "309",
           lines.count == 2 {
            report = try? JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any]
        } else {
            report = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        }
        guard looksLikeAppleCrashReport(text), let report else {
            return nil
        }

        var summary: [AppleCrashReportEntry] = []
        appendJSONValue(report, path: ["incident"], label: "Incident", to: &summary, severity: .info)
        appendJSONValue(report, path: ["procName"], label: "Process", to: &summary, severity: .info)
        appendJSONValue(report, path: ["bundleInfo", "CFBundleIdentifier"], label: "Identifier", to: &summary, severity: .info)
        appendJSONValue(report, path: ["bundleInfo", "CFBundleShortVersionString"], label: "Version", to: &summary, severity: .info)
        appendJSONValue(report, path: ["osVersion", "train"], label: "OS Version", to: &summary, severity: .info)
        appendJSONValue(report, path: ["timestamp"], label: "Date", to: &summary, severity: .info)

        var failure: [AppleCrashReportEntry] = []
        appendJSONValue(report, path: ["exception", "type"], label: "Exception Type", to: &failure, severity: .critical)
        appendJSONValue(report, path: ["exception", "codes"], label: "Exception Codes", to: &failure, severity: .warning)
        appendJSONValue(report, path: ["termination", "namespace"], label: "Termination Namespace", to: &failure, severity: .critical)
        appendJSONValue(report, path: ["termination", "reason"], label: "Termination Reason", to: &failure, severity: .critical)
        appendJSONValue(report, path: ["faultingThread"], label: "Crashed Thread", to: &failure, severity: .warning)

        var sections: [AppleCrashReportSection] = []
        if !summary.isEmpty {
            sections.append(AppleCrashReportSection(id: "summary", title: "Summary", entries: summary))
        }
        if !failure.isEmpty {
            sections.append(AppleCrashReportSection(id: "failure", title: "Crash Cause", entries: failure))
        }
        if let threads = report["threads"] as? [[String: Any]], !threads.isEmpty {
            let entries = threads.prefix(maximumThreadEntries).enumerated().map { index, thread in
                let name = stringValue(thread["name"]) ?? stringValue(thread["queue"]) ?? "Thread \(index)"
                let isCrashed = (thread["triggered"] as? Bool) == true
                return entry(key: isCrashed ? "Crashed thread" : "Thread", value: name, severity: isCrashed ? .critical : .info, index: index)
            }
            sections.append(AppleCrashReportSection(id: "threads", title: "Threads", entries: entries))
        }
        if let images = report["usedImages"] as? [[String: Any]], !images.isEmpty {
            let entries = [entry(key: "Images", value: "\(images.count) listed", severity: .info, index: 0)] + images.prefix(maximumBinaryImageEntries).enumerated().map { index, image in
                let name = stringValue(image["name"]) ?? stringValue(image["path"]) ?? "Image \(index + 1)"
                return entry(key: "Image", value: name, severity: .info, index: index + 1)
            }
            sections.append(AppleCrashReportSection(id: "images", title: "Binary Images", entries: entries))
        }
        return sections
    }

    nonisolated private static func appendJSONValue(
        _ report: [String: Any],
        path: [String],
        label: String,
        to entries: inout [AppleCrashReportEntry],
        severity: AppleCrashReportSeverity
    ) {
        guard let value = value(in: report, path: path).flatMap(stringValue) else { return }
        entries.append(entry(key: label, value: value, severity: severity, index: entries.count))
    }

    nonisolated private static func value(in dictionary: [String: Any], path: [String]) -> Any? {
        var current: Any = dictionary
        for component in path {
            guard let nested = current as? [String: Any], let value = nested[component] else { return nil }
            current = value
        }
        return current
    }

    nonisolated private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    nonisolated private static func entry(key: String, value: String, severity: AppleCrashReportSeverity, index: Int) -> AppleCrashReportEntry {
        AppleCrashReportEntry(id: "\(key)-\(index)-\(value.hashValue)", key: key, value: value, severity: severity)
    }
}

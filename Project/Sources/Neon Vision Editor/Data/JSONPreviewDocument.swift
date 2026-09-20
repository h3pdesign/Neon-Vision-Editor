import Foundation

/// A bounded preview projection; number spelling, key order and duplicate keys are preserved.
nonisolated struct JSONPreviewDocument: Sendable {
    static let maximumBytes = 16_000_000
    static let maximumNodes = 200_000
    static let pageSize = 100

    enum Kind: String, Sendable {
        case object, array, string, number, boolean, null
    }

    struct Node: Sendable {
        let name: String
        let kind: Kind
        let value: String
        let children: [Int]
    }

    struct Row: Identifiable, Sendable {
        let nodeID: Int
        let depth: Int
        let isPager: Bool
        var id: Int { isPager ? -nodeID - 1 : nodeID }
    }

    struct Failure: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    let nodes: [Node]

    static func parse(_ text: String) throws -> Self {
        guard text.utf8.count <= maximumBytes else {
            throw Failure(message: "Structured preview supports up to 16 MB. The source remains editable.")
        }
        var parser = Parser(bytes: Array(text.utf8))
        _ = try parser.value(name: "Root", depth: 0)
        try parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw parser.failure("Unexpected trailing content") }
        return Self(nodes: parser.nodes)
    }

    func rows(expanded: Set<Int>, pages: [Int: Int]) -> [Row] {
        var result: [Row] = []
        func append(_ id: Int, depth: Int) {
            guard result.count < 2_000 else { return }
            result.append(Row(nodeID: id, depth: depth, isPager: false))
            let children = nodes[id].children
            guard expanded.contains(id), !children.isEmpty else { return }
            let start = min(max(0, pages[id, default: 0]) * Self.pageSize, children.count - 1)
            for child in children[start..<min(start + Self.pageSize, children.count)] {
                append(child, depth: depth + 1)
            }
            if children.count > Self.pageSize, result.count < 2_000 {
                result.append(Row(nodeID: id, depth: depth + 1, isPager: true))
            }
        }
        if !nodes.isEmpty { append(0, depth: 0) }
        return result
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0
        var nodes: [Node] = []
        var current: UInt8? { offset < bytes.count ? bytes[offset] : nil }

        mutating func whitespace() throws {
            while let byte = current, [9, 10, 13, 32].contains(byte) {
                if offset % 4096 == 0 { try Task.checkCancellation() }
                offset += 1
            }
        }

        func failure(_ reason: String) -> Failure {
            let prefix = String(decoding: bytes.prefix(offset), as: UTF8.self)
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
            return Failure(message: "\(reason) at line \(lines.count), column \((lines.last?.count ?? 0) + 1).")
        }

        mutating func string() throws -> String {
            let start = offset
            offset += 1
            while let byte = current {
                if offset % 4096 == 0 { try Task.checkCancellation() }
                offset += 1
                if byte == 92 {
                    guard current != nil else { throw failure("Incomplete escape") }
                    offset += 1
                } else if byte == 34 {
                    do {
                        return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset]))
                    } catch {
                        throw failure("Invalid string or escape")
                    }
                } else if byte < 32 {
                    throw failure("Unescaped control character")
                }
            }
            throw failure("Unterminated string")
        }

        mutating func value(name: String, depth: Int) throws -> Int {
            try Task.checkCancellation()
            guard depth <= 128, nodes.count < JSONPreviewDocument.maximumNodes else {
                throw Failure(message: "Structured preview limit reached (128 levels or 200,000 values). The source remains editable.")
            }
            try whitespace()
            let id = nodes.count
            nodes.append(Node(name: name, kind: .null, value: "", children: []))
            let kind: Kind
            var display = ""
            var children: [Int] = []
            guard let token = current else { throw failure("Expected a JSON value") }
            switch token {
            case 123, 91:
                let object = current == 123
                kind = object ? .object : .array
                let end: UInt8 = object ? 125 : 93
                offset += 1
                try whitespace()
                if current != end {
                    while true {
                        var childName = "[\(children.count)]"
                        if object {
                            guard current == 34 else { throw failure("Expected an object key") }
                            childName = Self.clipped(try string(), limit: 256)
                            try whitespace()
                            guard current == 58 else { throw failure("Expected ':'") }
                            offset += 1
                        }
                        children.append(try value(name: childName, depth: depth + 1))
                        try whitespace()
                        if current == end { break }
                        guard current == 44 else { throw failure("Expected ',' or closing bracket") }
                        offset += 1
                        try whitespace()
                    }
                }
                offset += 1
                display = "\(children.count) \(object ? "properties" : "items")"
            case 34:
                kind = .string
                display = "\"\(Self.clipped(try string(), limit: 512))\""
            case 116, 102, 110:
                let literal = current == 116 ? "true" : current == 102 ? "false" : "null"
                guard bytes[offset...].starts(with: literal.utf8) else { throw failure("Invalid literal") }
                offset += literal.utf8.count
                kind = literal == "null" ? .null : .boolean
                display = literal
            case 45, 48...57:
                kind = .number
                let start = offset
                if current == 45 { offset += 1 }
                if current == 48 {
                    offset += 1
                } else {
                    guard let byte = current, (49...57).contains(byte) else { throw failure("Invalid number") }
                    try digits()
                }
                if current == 46 {
                    offset += 1
                    guard let byte = current, (48...57).contains(byte) else { throw failure("Expected fractional digits") }
                    try digits()
                }
                if current == 101 || current == 69 {
                    offset += 1
                    if current == 43 || current == 45 { offset += 1 }
                    guard let byte = current, (48...57).contains(byte) else { throw failure("Expected exponent digits") }
                    try digits()
                }
                display = String(decoding: bytes[start..<min(offset, start + 512)], as: UTF8.self)
                if offset - start > 512 { display += "…" }
            default:
                throw failure("Expected a JSON value")
            }
            nodes[id] = Node(name: name, kind: kind, value: display, children: children)
            return id
        }

        mutating func digits() throws {
            while let byte = current, (48...57).contains(byte) {
                if offset % 4096 == 0 { try Task.checkCancellation() }
                offset += 1
            }
        }

        static func clipped(_ text: String, limit: Int) -> String {
            let prefix = text.prefix(limit)
            return String(prefix) + (prefix.endIndex == text.endIndex ? "" : "…")
        }
    }
}

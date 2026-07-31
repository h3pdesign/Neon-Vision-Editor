import Foundation

struct DocumentDiff: Sendable {
    enum RowKind: Sendable {
        case equal
        case removed
        case inserted
        case changed
    }

    struct Row: Identifiable, Sendable {
        let id: Int
        let leftLineNumber: Int?
        let rightLineNumber: Int?
        let leftText: String
        let rightText: String
        let kind: RowKind

        nonisolated var isChanged: Bool {
            if case .equal = kind { return false }
            return true
        }
    }

    struct Hunk: Identifiable, Sendable {
        let id: Int
        let startRowID: Int
        let rowCount: Int

        var accessibilityLabel: String {
            "Change \(id + 1), \(rowCount) \(rowCount == 1 ? "row" : "rows")"
        }
    }

    let rows: [Row]
    let hunks: [Hunk]
}

struct DocumentDiffPresentation: Identifiable, Sendable {
    let id: UUID
    let title: String
    let leftTitle: String
    let rightTitle: String
    let diff: DocumentDiff
    let changedRows: [DocumentDiff.Row]
    let language: String?

    nonisolated init(
        title: String,
        leftTitle: String,
        rightTitle: String,
        diff: DocumentDiff,
        language: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.leftTitle = leftTitle
        self.rightTitle = rightTitle
        self.diff = diff
        self.changedRows = diff.rows.filter(\.isChanged)
        self.language = language
    }
}

enum DocumentDiffBuilder {
    private enum Operation {
        case equal(String)
        case remove(String)
        case insert(String)
    }

    nonisolated private static let guardedDiffUTF8ByteThreshold = 8_000_000
    nonisolated private static let guardedDiffUTF16LengthThreshold = 1_000_000
    nonisolated private static let maxDynamicProgrammingCells = 1_200_000

    nonisolated static func build(leftContent: String, rightContent: String) -> DocumentDiff {
        if shouldReturnGuardedDiff(leftContent: leftContent, rightContent: rightContent) {
            return guardedDiff(leftContent: leftContent, rightContent: rightContent)
        }
        let leftLines = splitLines(leftContent)
        let rightLines = splitLines(rightContent)
        let operations = diffOperations(leftLines: leftLines, rightLines: rightLines)
        let rows = rows(from: operations)
        return DocumentDiff(rows: rows, hunks: hunks(from: rows))
    }

    nonisolated private static func shouldReturnGuardedDiff(leftContent: String, rightContent: String) -> Bool {
        (leftContent as NSString).length >= guardedDiffUTF16LengthThreshold ||
        (rightContent as NSString).length >= guardedDiffUTF16LengthThreshold ||
        leftContent.utf8.count >= guardedDiffUTF8ByteThreshold ||
        rightContent.utf8.count >= guardedDiffUTF8ByteThreshold
    }

    nonisolated private static func guardedDiff(leftContent: String, rightContent: String) -> DocumentDiff {
        let leftSummary = guardedSummary(for: leftContent)
        let rightSummary = guardedSummary(for: rightContent)
        let rows = [
            DocumentDiff.Row(
                id: 0,
                leftLineNumber: 1,
                rightLineNumber: 1,
                leftText: "Large file diff skipped for responsiveness (\(leftSummary)).",
                rightText: "Large file diff skipped for responsiveness (\(rightSummary)).",
                kind: .changed
            )
        ]
        return DocumentDiff(rows: rows, hunks: hunks(from: rows))
    }

    nonisolated private static func guardedSummary(for content: String) -> String {
        let utf16Length = (content as NSString).length
        let bytes = content.utf8.count
        return "\(utf16Length) UTF-16 units, \(bytes) bytes"
    }

    nonisolated private static func splitLines(_ content: String) -> [String] {
        if content.isEmpty { return [] }
        return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    nonisolated private static func diffOperations(leftLines: [String], rightLines: [String]) -> [Operation] {
        var prefixCount = 0
        let sharedPrefixLimit = min(leftLines.count, rightLines.count)
        while prefixCount < sharedPrefixLimit && leftLines[prefixCount] == rightLines[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount < leftLines.count - prefixCount &&
            suffixCount < rightLines.count - prefixCount &&
            leftLines[leftLines.count - 1 - suffixCount] == rightLines[rightLines.count - 1 - suffixCount] {
            suffixCount += 1
        }

        var operations: [Operation] = leftLines.prefix(prefixCount).map(Operation.equal)
        let leftMiddle = Array(leftLines[prefixCount..<(leftLines.count - suffixCount)])
        let rightMiddle = Array(rightLines[prefixCount..<(rightLines.count - suffixCount)])
        operations.append(contentsOf: middleOperations(leftLines: leftMiddle, rightLines: rightMiddle))
        operations.append(contentsOf: leftLines.suffix(suffixCount).map(Operation.equal))
        return operations
    }

    nonisolated private static func middleOperations(leftLines: [String], rightLines: [String]) -> [Operation] {
        guard !leftLines.isEmpty else { return rightLines.map(Operation.insert) }
        guard !rightLines.isEmpty else { return leftLines.map(Operation.remove) }

        let cellCount = leftLines.count * rightLines.count
        guard cellCount <= maxDynamicProgrammingCells else {
            return largeRegionOperations(leftLines: leftLines, rightLines: rightLines)
        }

        return dynamicProgrammingOperations(leftLines: leftLines, rightLines: rightLines)
    }

    nonisolated private static func dynamicProgrammingOperations(leftLines: [String], rightLines: [String]) -> [Operation] {
        let columns = rightLines.count + 1
        var table = Array(repeating: 0, count: (leftLines.count + 1) * columns)

        for leftIndex in stride(from: leftLines.count - 1, through: 0, by: -1) {
            for rightIndex in stride(from: rightLines.count - 1, through: 0, by: -1) {
                let offset = leftIndex * columns + rightIndex
                if leftLines[leftIndex] == rightLines[rightIndex] {
                    table[offset] = table[(leftIndex + 1) * columns + rightIndex + 1] + 1
                } else {
                    table[offset] = max(
                        table[(leftIndex + 1) * columns + rightIndex],
                        table[leftIndex * columns + rightIndex + 1]
                    )
                }
            }
        }

        var operations: [Operation] = []
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < leftLines.count && rightIndex < rightLines.count {
            if leftLines[leftIndex] == rightLines[rightIndex] {
                operations.append(.equal(leftLines[leftIndex]))
                leftIndex += 1
                rightIndex += 1
            } else if table[(leftIndex + 1) * columns + rightIndex] >= table[leftIndex * columns + rightIndex + 1] {
                operations.append(.remove(leftLines[leftIndex]))
                leftIndex += 1
            } else {
                operations.append(.insert(rightLines[rightIndex]))
                rightIndex += 1
            }
        }
        while leftIndex < leftLines.count {
            operations.append(.remove(leftLines[leftIndex]))
            leftIndex += 1
        }
        while rightIndex < rightLines.count {
            operations.append(.insert(rightLines[rightIndex]))
            rightIndex += 1
        }
        return operations
    }

    // Git's patience/histogram strategies avoid treating a large shifted region
    // as one delete-all/insert-all operation. Unique common lines become stable
    // anchors; only the smaller regions between anchors use the exact LCS pass.
    nonisolated private static func largeRegionOperations(leftLines: [String], rightLines: [String]) -> [Operation] {
        let leftCounts = lineCounts(leftLines)
        let rightCounts = lineCounts(rightLines)
        let candidates = leftLines.enumerated().compactMap { leftIndex, line -> (Int, Int)? in
            guard leftCounts[line] == 1, rightCounts[line] == 1,
                  let rightIndex = rightLines.firstIndex(of: line) else { return nil }
            return (leftIndex, rightIndex)
        }
        let anchors = longestIncreasingAnchors(candidates)
        guard !anchors.isEmpty else {
            return leftLines.map(Operation.remove) + rightLines.map(Operation.insert)
        }

        var operations: [Operation] = []
        var leftStart = 0
        var rightStart = 0
        for (leftIndex, rightIndex) in anchors {
            operations.append(contentsOf: regionOperations(
                leftLines: Array(leftLines[leftStart..<leftIndex]),
                rightLines: Array(rightLines[rightStart..<rightIndex])
            ))
            operations.append(.equal(leftLines[leftIndex]))
            leftStart = leftIndex + 1
            rightStart = rightIndex + 1
        }
        operations.append(contentsOf: regionOperations(
            leftLines: Array(leftLines[leftStart...]),
            rightLines: Array(rightLines[rightStart...])
        ))
        return operations
    }

    nonisolated private static func regionOperations(leftLines: [String], rightLines: [String]) -> [Operation] {
        guard !leftLines.isEmpty else { return rightLines.map(Operation.insert) }
        guard !rightLines.isEmpty else { return leftLines.map(Operation.remove) }
        if leftLines.count * rightLines.count <= maxDynamicProgrammingCells {
            return dynamicProgrammingOperations(leftLines: leftLines, rightLines: rightLines)
        }
        return largeRegionOperations(leftLines: leftLines, rightLines: rightLines)
    }

    nonisolated private static func lineCounts(_ lines: [String]) -> [String: Int] {
        lines.reduce(into: [:]) { counts, line in counts[line, default: 0] += 1 }
    }

    nonisolated private static func longestIncreasingAnchors(_ candidates: [(Int, Int)]) -> [(Int, Int)] {
        guard !candidates.isEmpty else { return [] }
        var lengths = Array(repeating: 1, count: candidates.count)
        var predecessors = Array(repeating: -1, count: candidates.count)
        var bestIndex = 0

        for index in candidates.indices {
            for previous in 0..<index where candidates[previous].1 < candidates[index].1 {
                if lengths[previous] + 1 > lengths[index] {
                    lengths[index] = lengths[previous] + 1
                    predecessors[index] = previous
                }
            }
            if lengths[index] > lengths[bestIndex] {
                bestIndex = index
            }
        }

        var result: [(Int, Int)] = []
        var index = bestIndex
        while index >= 0 {
            result.append(candidates[index])
            index = predecessors[index]
        }
        return result.reversed()
    }

    nonisolated private static func rows(from operations: [Operation]) -> [DocumentDiff.Row] {
        var rows: [DocumentDiff.Row] = []
        var leftLineNumber = 1
        var rightLineNumber = 1
        var index = 0

        func appendEqual(_ text: String) {
            rows.append(
                DocumentDiff.Row(
                    id: rows.count,
                    leftLineNumber: leftLineNumber,
                    rightLineNumber: rightLineNumber,
                    leftText: text,
                    rightText: text,
                    kind: .equal
                )
            )
            leftLineNumber += 1
            rightLineNumber += 1
        }

        while index < operations.count {
            switch operations[index] {
            case let .equal(text):
                appendEqual(text)
                index += 1
            case .remove, .insert:
                var removed: [String] = []
                var inserted: [String] = []
                while index < operations.count {
                    switch operations[index] {
                    case let .remove(text):
                        removed.append(text)
                    case let .insert(text):
                        inserted.append(text)
                    case .equal:
                        break
                    }
                    if case .equal = operations[index] { break }
                    index += 1
                }

                let pairedCount = max(removed.count, inserted.count)
                for pairIndex in 0..<pairedCount {
                    let leftText = pairIndex < removed.count ? removed[pairIndex] : ""
                    let rightText = pairIndex < inserted.count ? inserted[pairIndex] : ""
                    let leftNumber = pairIndex < removed.count ? leftLineNumber : nil
                    let rightNumber = pairIndex < inserted.count ? rightLineNumber : nil
                    let kind: DocumentDiff.RowKind
                    if pairIndex < removed.count && pairIndex < inserted.count {
                        kind = .changed
                    } else if pairIndex < removed.count {
                        kind = .removed
                    } else {
                        kind = .inserted
                    }
                    rows.append(
                        DocumentDiff.Row(
                            id: rows.count,
                            leftLineNumber: leftNumber,
                            rightLineNumber: rightNumber,
                            leftText: leftText,
                            rightText: rightText,
                            kind: kind
                        )
                    )
                    if pairIndex < removed.count { leftLineNumber += 1 }
                    if pairIndex < inserted.count { rightLineNumber += 1 }
                }
            }
        }

        return rows
    }

    nonisolated private static func hunks(from rows: [DocumentDiff.Row]) -> [DocumentDiff.Hunk] {
        var hunks: [DocumentDiff.Hunk] = []
        var index = 0
        while index < rows.count {
            guard rows[index].isChanged else {
                index += 1
                continue
            }
            let start = index
            while index < rows.count && rows[index].isChanged {
                index += 1
            }
            hunks.append(
                DocumentDiff.Hunk(
                    id: hunks.count,
                    startRowID: rows[start].id,
                    rowCount: index - start
                )
            )
        }
        return hunks
    }
}

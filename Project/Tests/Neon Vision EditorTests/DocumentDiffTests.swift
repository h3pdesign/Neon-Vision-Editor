import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class DocumentDiffTests: XCTestCase {
    func testBuildMarksChangedRowsAndHunks() {
        let diff = DocumentDiffBuilder.build(
            leftContent: "one\ntwo\nthree\n",
            rightContent: "one\nTWO\nthree\n"
        )

        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertTrue(isEqual(diff.rows[0].kind))
        XCTAssertTrue(isChanged(diff.rows[1].kind))
        XCTAssertTrue(isEqual(diff.rows[2].kind))
        XCTAssertTrue(isEqual(diff.rows[3].kind))
        XCTAssertEqual(diff.rows[1].leftText, "two")
        XCTAssertEqual(diff.rows[1].rightText, "TWO")
    }

    func testBuildKeepsInsertionsNavigable() {
        let diff = DocumentDiffBuilder.build(
            leftContent: "one\nthree",
            rightContent: "one\ntwo\nthree"
        )

        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertTrue(diff.rows.contains { isInserted($0.kind) && $0.rightText == "two" })
    }

    func testBuildKeepsRemovalsNavigable() {
        let diff = DocumentDiffBuilder.build(
            leftContent: "one\ntwo\nthree",
            rightContent: "one\nthree"
        )

        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertTrue(diff.rows.contains { isRemoved($0.kind) && $0.leftText == "two" })
    }

    func testBuildReturnsGuardedSummaryForHugeInputsBeforeFullDiff() {
        let huge = String(repeating: "a", count: 8_000_000)
        let diff = DocumentDiffBuilder.build(
            leftContent: huge,
            rightContent: huge + "b"
        )

        XCTAssertEqual(diff.rows.count, 1)
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertTrue(isChanged(diff.rows[0].kind))
        XCTAssertTrue(diff.rows[0].leftText.contains("Large file diff skipped"))
        XCTAssertTrue(diff.rows[0].rightText.contains("Large file diff skipped"))
    }

    func testBuildKeepsLargeChangedRegionAsOneNavigableHunk() {
        let left = (0..<1_000).map { "old line \($0)" }.joined(separator: "\n")
        let right = (0..<1_000).map { "new line \($0)" }.joined(separator: "\n")

        let diff = DocumentDiffBuilder.build(leftContent: left, rightContent: right)

        XCTAssertEqual(diff.rows.count, 1_000)
        XCTAssertEqual(diff.hunks.count, 1)
        XCTAssertEqual(diff.hunks[0].rowCount, 1_000)
        XCTAssertTrue(diff.rows.allSatisfy(\.isChanged))
    }

    func testBuildUsesStableAnchorsForLargeShiftedRegions() {
        let left = (0..<1_600).map { index in
            index.isMultiple(of: 40) ? "anchor-\(index)" : "old line \(index)"
        }.joined(separator: "\n")
        let right = (0..<1_600).map { index in
            index.isMultiple(of: 40) ? "anchor-\(index)" : "new line \(index)"
        }.joined(separator: "\n")

        let diff = DocumentDiffBuilder.build(leftContent: left, rightContent: right)

        XCTAssertGreaterThan(diff.rows.filter { if case .equal = $0.kind { return true }; return false }.count, 0)
        XCTAssertGreaterThan(diff.hunks.count, 1)
    }

    func testPresentationPrecomputesStableRowsForBothDisplayModes() {
        let diff = DocumentDiffBuilder.build(
            leftContent: "header\nold\ncontext one\ncontext two\ncontext three",
            rightContent: "header\nnew\ncontext one\ncontext two\ncontext three"
        )

        let presentation = DocumentDiffPresentation(
            title: "Comparison",
            leftTitle: "Before",
            rightTitle: "After",
            diff: diff
        )

        XCTAssertEqual(presentation.changedRows.map(\.id), diff.rows.filter(\.isChanged).map(\.id))
        XCTAssertEqual(Set(presentation.sideBySideRows.map(\.id)).count, presentation.sideBySideRows.count)
        XCTAssertEqual(Set(presentation.inlineRows.map(\.id)).count, presentation.inlineRows.count)
        XCTAssertTrue(presentation.sideBySideRows.contains { row in
            if case .unchanged = row { return true }
            return false
        })
        XCTAssertTrue(presentation.inlineRows.contains { row in
            if case .unifiedLine(_, .removed) = row { return true }
            return false
        })
        XCTAssertTrue(presentation.inlineRows.contains { row in
            if case .unifiedLine(_, .inserted) = row { return true }
            return false
        })
    }

    func testIgnoringWhitespaceHighlightsOnlyTheChangedJSONValue() {
        let left = "{\n  \"name\": \"Neon\",\n  \"count\": 1,\n  \"tags\": [\"a\", \"b\"]\n}"
        let right = "{\n    \"name\":\"Neon\",\n    \"count\":2,\n    \"tags\":[\"a\",\"b\"]\n}"

        let strict = DocumentDiffBuilder.build(leftContent: left, rightContent: right)
        XCTAssertEqual(strict.rows.filter(\.isChanged).count, 3)

        let diff = DocumentDiffBuilder.build(leftContent: left, rightContent: right, ignoringWhitespace: true)
        XCTAssertEqual(diff.hunks.count, 1)
        let changed = diff.rows.filter(\.isChanged)
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(changed.first?.leftText, "  \"count\": 1,")
        XCTAssertEqual(changed.first?.rightText, "    \"count\":2,")
        XCTAssertEqual(changed.first?.leftLineNumber, 3)
        XCTAssertEqual(changed.first?.rightLineNumber, 3)
        // Equal rows keep each side's original text.
        XCTAssertEqual(diff.rows[1].leftText, "  \"name\": \"Neon\",")
        XCTAssertEqual(diff.rows[1].rightText, "    \"name\":\"Neon\",")
    }

    func testIgnoringWhitespaceKeepsOriginalTextAcrossInsertionsAndRemovals() {
        let diff = DocumentDiffBuilder.build(
            leftContent: "a\n  b\nc\n  d",
            rightContent: "a\nb\nnew\nc",
            ignoringWhitespace: true
        )

        XCTAssertEqual(diff.rows.map(\.leftText), ["a", "  b", "", "c", "  d"])
        XCTAssertEqual(diff.rows.map(\.rightText), ["a", "b", "new", "c", ""])
        XCTAssertTrue(isInserted(diff.rows[2].kind))
        XCTAssertTrue(isRemoved(diff.rows[4].kind))
        XCTAssertEqual(diff.rows.compactMap(\.leftLineNumber), [1, 2, 3, 4])
        XCTAssertEqual(diff.rows.compactMap(\.rightLineNumber), [1, 2, 3, 4])
    }

    func testPresentationRebuildsWithWhitespaceOptionFromKeptSources() {
        let presentation = DocumentDiffPresentation.make(
            title: "Compare",
            leftTitle: "Left",
            rightTitle: "Right",
            leftContent: "{\n  \"a\": 1\n}",
            rightContent: "{\n\t\"a\": 1\n}",
            ignoresWhitespace: false
        )
        XCTAssertEqual(presentation.changedRows.count, 1)

        let rebuilt = presentation.rebuilt(ignoringWhitespace: true)
        XCTAssertEqual(rebuilt?.ignoresWhitespace, true)
        XCTAssertEqual(rebuilt?.changedRows.count, 0)
        XCTAssertEqual(rebuilt?.title, "Compare")

        let prebuilt = DocumentDiffPresentation(
            title: "Prebuilt",
            leftTitle: "Left",
            rightTitle: "Right",
            diff: presentation.diff
        )
        XCTAssertNil(prebuilt.rebuilt(ignoringWhitespace: true))
    }

    private func isEqual(_ kind: DocumentDiff.RowKind) -> Bool {
        if case .equal = kind { return true }
        return false
    }

    private func isChanged(_ kind: DocumentDiff.RowKind) -> Bool {
        if case .changed = kind { return true }
        return false
    }

    private func isInserted(_ kind: DocumentDiff.RowKind) -> Bool {
        if case .inserted = kind { return true }
        return false
    }

    private func isRemoved(_ kind: DocumentDiff.RowKind) -> Bool {
        if case .removed = kind { return true }
        return false
    }
}

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

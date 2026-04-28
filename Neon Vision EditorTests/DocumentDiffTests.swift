import XCTest
@testable import Neon_Vision_Editor

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

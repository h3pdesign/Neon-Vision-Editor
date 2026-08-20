import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class CodeSnapshotComposerTests: XCTestCase {
    private let payload = CodeSnapshotPayload(
        title: "Example.swift",
        language: "swift",
        text: "let value = 42\nprint(value)"
    )

    func testRatioPresetsProduceExpectedExportDimensions() {
        var style = CodeSnapshotStyle()

        style.sizePreset = .square
        XCTAssertEqual(CodeSnapshotSizing.dimensions(payload: payload, style: style), CGSize(width: 1200, height: 1200))

        style.sizePreset = .classic
        XCTAssertEqual(CodeSnapshotSizing.dimensions(payload: payload, style: style), CGSize(width: 1200, height: 900))

        style.sizePreset = .widescreen
        XCTAssertEqual(CodeSnapshotSizing.dimensions(payload: payload, style: style), CGSize(width: 1600, height: 900))

        style.sizePreset = .portrait
        XCTAssertEqual(CodeSnapshotSizing.dimensions(payload: payload, style: style), CGSize(width: 1080, height: 1920))
    }

    func testFitContentExpandsForLongerCode() {
        let short = CodeSnapshotSizing.dimensions(payload: payload, style: CodeSnapshotStyle())
        let longPayload = CodeSnapshotPayload(
            title: "Example.swift",
            language: "swift",
            text: String(repeating: "let value = 42\n", count: 40) + String(repeating: "x", count: 120)
        )
        let long = CodeSnapshotSizing.dimensions(payload: longPayload, style: CodeSnapshotStyle())

        XCTAssertGreaterThan(long.width, short.width)
        XCTAssertGreaterThan(long.height, short.height)
    }

    func testCustomDimensionsAreClampedToSafeExportBounds() {
        var style = CodeSnapshotStyle()
        style.sizePreset = .custom
        style.customCardWidth = 100
        style.customCardHeight = 9_000

        XCTAssertEqual(
            CodeSnapshotSizing.dimensions(payload: payload, style: style),
            CGSize(width: 480, height: 3200)
        )
    }
}

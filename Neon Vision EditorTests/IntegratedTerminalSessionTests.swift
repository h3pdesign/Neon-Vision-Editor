import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
@MainActor
final class IntegratedTerminalSessionTests: XCTestCase {
    func testTerminalDisplaySanitizerRemovesANSIControlSequencesAcrossChunks() {
        let sanitizer = TerminalDisplaySanitizer()

        XCTAssertEqual(sanitizer.displayText(from: "\u{1B}[?2004"), "")
        XCTAssertEqual(sanitizer.displayText(from: "hready\u{1B}[0m\n"), "ready\n")
        XCTAssertEqual(sanitizer.displayText(from: "prompt\r\n"), "prompt\n")
    }

    func testTerminalANSIFormatterPreservesColorAcrossChunks() {
        let formatter = TerminalANSIFormatter()

        let firstChunk = formatter.attributedText(from: "\u{1B}[31mred")
        let secondChunk = formatter.attributedText(from: " text\u{1B}[0m plain")
        let combined = NSMutableAttributedString(attributedString: firstChunk)
        combined.append(secondChunk)

        XCTAssertEqual(combined.string, "red text plain")
        XCTAssertNotNil(combined.attribute(.foregroundColor, at: 0, effectiveRange: nil))
        XCTAssertNil(combined.attribute(.foregroundColor, at: combined.length - 1, effectiveRange: nil))
    }

    func testPythonRuntimeShellQuotePreservesSpecialCharacters() {
        XCTAssertEqual(PythonRuntimeResolver.shellQuote("/tmp/My Script.py"), "'/tmp/My Script.py'")
        XCTAssertEqual(PythonRuntimeResolver.shellQuote("a'b"), "'a'\\''b'")
    }

    func testPTYSessionRunsACommandAndStopsCleanly() {
        let session = IntegratedTerminalSession()
        let marker = "NVE_PTY_TEST_\(UUID().uuidString)"

        session.startIfNeeded(in: FileManager.default.temporaryDirectory)
        XCTAssertTrue(session.isRunning)
        XCTAssertTrue(session.usesPTY)

        session.send("test -t 0 && test -t 1 && printf '\(marker)'", in: FileManager.default.temporaryDirectory)
        let deadline = Date().addingTimeInterval(3)
        while !session.output.contains(marker), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(session.output.contains(marker))
        XCTAssertFalse(session.output.localizedCaseInsensitiveContains("can't set tty pgrp"))
        session.stop()
        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(session.usesPTY)
    }
}
#endif

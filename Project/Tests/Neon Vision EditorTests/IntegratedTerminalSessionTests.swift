import XCTest
import Combine
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

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
        XCTAssertEqual(
            combined.attribute(.foregroundColor, at: combined.length - 1, effectiveRange: nil) as? NSColor,
            .textColor
        )
        XCTAssertEqual(
            (combined.attribute(.font, at: combined.length - 1, effectiveRange: nil) as? NSFont)?.pointSize,
            12
        )
    }

    func testTerminalOutputTextViewWrapsAndUsesSemanticTextColor() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let textView = NSTextView(frame: scrollView.contentView.bounds)

        TerminalOutputTextView.configure(scrollView: scrollView, textView: textView)

        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertFalse(textView.isHorizontallyResizable)
        XCTAssertTrue(textView.autoresizingMask.contains(.width))
        XCTAssertTrue(textView.textContainer?.widthTracksTextView == true)
        XCTAssertEqual(textView.textColor, .textColor)
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
        let deadline = Date().addingTimeInterval(10)
        while !session.output.contains(marker), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(session.output.contains(marker))
        XCTAssertFalse(session.output.localizedCaseInsensitiveContains("can't set tty pgrp"))
        session.stop()
        XCTAssertFalse(session.isRunning)
        XCTAssertFalse(session.usesPTY)
    }

    func testTerminalShellDisablesLineEditorRedrawAndPrefersLocalTools() {
        XCTAssertEqual(
            IntegratedTerminalSession.shellArguments,
            ["zsh", "-d", "-l", "-o", "NO_MONITOR", "-o", "NO_ZLE"]
        )
        XCTAssertEqual(
            IntegratedTerminalSession.commandSearchPath(inheritedPath: "/usr/bin:/bin:/opt/homebrew/bin"),
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        )
    }

    func testPTYResolvesInstalledHomebrewPythonBeforeAppleShim() throws {
        let interpreter = "/opt/homebrew/bin/python3"
        guard FileManager.default.isExecutableFile(atPath: interpreter) else {
            throw XCTSkip("Homebrew Python is not installed on this host.")
        }
        let session = IntegratedTerminalSession()
        let marker = "NVE_HOMEBREW_PYTHON_\(UUID().uuidString)"
        let encodedMarker = marker.utf8.map(String.init).joined(separator: ",")

        session.startIfNeeded(in: FileManager.default.temporaryDirectory)
        session.send(
            "python3 -c 'print(bytes([\(encodedMarker)]).decode())'",
            in: FileManager.default.temporaryDirectory
        )

        let deadline = Date().addingTimeInterval(10)
        while !session.output.contains(marker), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertTrue(session.output.contains(marker), session.output)
        session.stop()
    }

    func testStoppingSessionTerminatesForegroundProcessGroup() {
        let session = IntegratedTerminalSession()
        let marker = "NVE_PTY_CHILD_\(UUID().uuidString)"
        session.startIfNeeded(in: FileManager.default.temporaryDirectory)
        session.send("sleep 30 & child=$!; printf '\(marker):%s\\n' \"$child\"", in: FileManager.default.temporaryDirectory)

        let outputDeadline = Date().addingTimeInterval(3)
        var pid: pid_t?
        while pid == nil, Date() < outputDeadline {
            pid = childPID(in: session.output, marker: marker)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(pid)

        session.stop()
        guard let pid else { return }
        let exitDeadline = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0, Date() < exitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(kill(pid, 0), -1)
    }

    func testStoppingSessionEscalatesForAChildThatIgnoresTermination() {
        let session = IntegratedTerminalSession()
        let marker = "NVE_PTY_STUBBORN_CHILD_\(UUID().uuidString)"
        session.startIfNeeded(in: FileManager.default.temporaryDirectory)
        session.send("sh -c 'trap \"\" TERM; sleep 30' & child=$!; printf '\(marker):%s\\n' \"$child\"", in: FileManager.default.temporaryDirectory)

        let outputDeadline = Date().addingTimeInterval(3)
        var pid: pid_t?
        while pid == nil, Date() < outputDeadline {
            pid = childPID(in: session.output, marker: marker)
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertNotNil(pid)

        session.stop()
        guard let pid else { return }
        let exitDeadline = Date().addingTimeInterval(3)
        while kill(pid, 0) == 0, Date() < exitDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(kill(pid, 0), -1)
    }

    func testHighVolumeOutputPublishesBoundedIncrementalChunks() {
        let session = IntegratedTerminalSession()
        let markerPrefix = "NVE_PTY_VOLUME_"
        let markerSuffix = UUID().uuidString
        let marker = markerPrefix + markerSuffix
        var appendLengths: [Int] = []
        let observation = session.$renderUpdate.dropFirst().sink { update in
            if case .append(let chunk) = update.kind {
                appendLengths.append(chunk.length)
            }
        }

        session.startIfNeeded(in: FileManager.default.temporaryDirectory)
        session.send(
            "i=0; while [ $i -lt 16000 ]; do printf 'line-%05d-abcdefghijklmnopqrstuvwxyz\\n' $i; i=$((i+1)); done; printf '%s%s\\n' '\(markerPrefix)' '\(markerSuffix)'",
            in: FileManager.default.temporaryDirectory
        )

        let deadline = Date().addingTimeInterval(15)
        while !session.output.contains(marker), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let publicationDeadline = Date().addingTimeInterval(2)
        while appendLengths.isEmpty, Date() < publicationDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        XCTAssertTrue(session.output.contains(marker))
        XCTAssertLessThanOrEqual((session.output as NSString).length, IntegratedTerminalSession.maxOutputUTF16Length + 30)
        XCTAssertLessThanOrEqual(session.styledOutputSnapshot().length, IntegratedTerminalSession.maxOutputUTF16Length)
        XCTAssertFalse(appendLengths.isEmpty)
        XCTAssertLessThanOrEqual(appendLengths.max() ?? 0, IntegratedTerminalSession.maxOutputUTF16Length)
        observation.cancel()
        session.stop()
    }

    func testTerminalOutputTextViewAppliesIncrementalUpdatesAndRecoversSkippedRevisions() {
        let textView = NSTextView()
        let coordinator = TerminalOutputTextView.Coordinator()
        coordinator.install(NSAttributedString(string: ""), revision: 0, in: textView)
        XCTAssertEqual(textView.string, "Ready.")
        XCTAssertEqual(
            textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .textColor
        )
        XCTAssertEqual(
            (textView.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize,
            12
        )

        coordinator.apply(
            TerminalRenderUpdate(revision: 1, kind: .append(NSAttributedString(string: "first"))),
            fallbackSnapshot: { NSAttributedString(string: "unused") },
            in: textView
        )
        XCTAssertEqual(textView.string, "first")

        coordinator.apply(
            TerminalRenderUpdate(revision: 3, kind: .append(NSAttributedString(string: "third"))),
            fallbackSnapshot: { NSAttributedString(string: "recovered") },
            in: textView
        )
        XCTAssertEqual(textView.string, "recovered")
    }

    private func childPID(in output: String, marker: String) -> pid_t? {
        output
            .split(separator: "\n")
            .compactMap { line -> pid_t? in
                guard let markerRange = line.range(of: marker + ":") else { return nil }
                let value = line[markerRange.upperBound...].trimmingCharacters(in: .whitespaces)
                guard let processID = Int32(value), processID > 0 else { return nil }
                return pid_t(processID)
            }
            .last
    }
}
#endif

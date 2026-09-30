import XCTest
import Combine
@testable import Neon_Vision_Editor

#if os(macOS)
import AppKit

@MainActor
final class IntegratedTerminalSessionTests: XCTestCase {
    func testScreenPreservesUTF8AtEveryByteBoundaryAndRepairsMalformedBytes() {
        let text = "e\u{301} 中文 👩‍💻 🇩🇰\r\n"
        let bytes = Data(text.utf8)
        for split in 0...bytes.count {
            let screen = TerminalScreenBuffer()
            let output = NSMutableAttributedString()
            for chunk in [Data(bytes.prefix(split)), Data(bytes.dropFirst(split))] {
                screen.consume(chunk)
                if let patch = screen.takePatch() {
                    output.replaceCharacters(in: patch.range, with: patch.text)
                }
            }
            XCTAssertEqual(output.string, text.replacingOccurrences(of: "\r", with: ""), "split \(split)")
        }
        let decoder = TerminalUTF8Decoder()
        XCTAssertEqual(decoder.decode(Data([0xE2])), "")
        XCTAssertEqual(decoder.decode(Data([0x41, 0xFF])), "\u{FFFD}A\u{FFFD}")
        decoder.reset()
        XCTAssertEqual(decoder.decode(Data("ready".utf8)), "ready")
    }

    func testScreenRewritesProgressAndHandlesCursorEraseAndTabCommands() {
        XCTAssertEqual(screenText(["Downloading 10%", "\rDownloading 100%\u{1B}[K"]), "Downloading 100%")
        XCTAssertEqual(screenText(["abcdef", "\u{8}\u{8}XY"]), "abcdXY")
        XCTAssertEqual(screenText(["abc\r\nsecond", "\u{1B}[1A\u{1B}[2GZ"]), "aZc\nsecond")
        XCTAssertEqual(screenText(["abcdef", "\u{1B}[3G\u{1B}[0KQ"]), "abQ")
        XCTAssertEqual(screenText(["abcdef", "\u{1B}[3G\u{1B}[1K"]), "   def")
        XCTAssertEqual(screenText(["abc\r\nsecond", "\u{1B}[2J\u{1B}[1;1Hnew"]), "new\n")
        XCTAssertEqual(screenText(["a\tb"]), "a       b")
    }

    func testScreenWideCharactersCombiningMarksAndResizeKeepColumnSemantics() {
        XCTAssertEqual(screenText(["中x\r\u{1B}[2Gy"]), " yx")
        XCTAssertEqual(screenText(["e", "\u{301}\rZ"]), "Z")
        let screen = TerminalScreenBuffer()
        screen.resize(columns: 4, rows: 2)
        screen.consume(Data("abcdEF".utf8))
        XCTAssertEqual(screen.takePatch()?.text.string, "abcd\nEF")
        screen.resize(columns: 8, rows: 4)
        screen.consume(Data("GH".utf8))
        let patch = screen.takePatch()
        XCTAssertEqual(patch?.text.string, "EFGH")
    }

    func testScreenSuppressesFragmentedOSCAndUnsupportedControlsAndBoundsCSI() {
        XCTAssertEqual(screenText(["a\u{1B}]0;private", " title\u{1B}", "\\b"]), "ab")
        XCTAssertEqual(screenText(["a\u{1B}Pdiscard", "\u{1B}\\b\u{1B}[?1049hc"]), "abc")
        XCTAssertEqual(screenText(["a\u{1B}[" + String(repeating: "1", count: 10_000), "mb"]), "ab")
        XCTAssertEqual(screenText(["\u{1B}[31", "mred\u{1B}[0m plain"]), "red plain")
    }

    func testScreenPreservesSGRAndPublishesOnlyTheRewrittenSuffix() {
        let screen = TerminalScreenBuffer()
        screen.consume(Data("history\r\n\u{1B}[31mred".utf8))
        let first = screen.takePatch()!
        let redColor = first.text.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
        XCTAssertNotEqual(redColor, .textColor)
        screen.consume(Data("\r\u{1B}[0mnew\u{1B}[K".utf8))
        let second = screen.takePatch()!
        XCTAssertEqual(second.range, NSRange(location: 8, length: 3))
        XCTAssertEqual(second.text.string, "new")
        XCTAssertEqual(second.text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor, .textColor)
        XCTAssertNil(screen.takePatch())
    }

    func testScreenBoundsHistoryAndNeverSplitsRetainedGraphemes() {
        let screen = TerminalScreenBuffer(maximumUTF16Length: 2_048)
        screen.resize(columns: 80, rows: 4)
        let output = NSMutableAttributedString()
        for _ in 0..<100 {
            screen.consume(Data((String(repeating: "👩‍💻e\u{301}", count: 10) + "\r\n").utf8))
            if let patch = screen.takePatch() { output.replaceCharacters(in: patch.range, with: patch.text) }
        }
        XCTAssertLessThanOrEqual(output.length, 2_048)
        XCTAssertFalse(output.string.contains("\u{FFFD}"))
        screen.consume(Data(("a" + String(repeating: "\u{301}", count: 10_000)).utf8))
        if let patch = screen.takePatch() { output.replaceCharacters(in: patch.range, with: patch.text) }
        XCTAssertLessThanOrEqual(output.length, 2_048)
        screen.reset()
        screen.consume(Data("clean".utf8))
        XCTAssertEqual(screen.takePatch()?.text.string, "clean")
    }

    private func screenText(_ chunks: [String]) -> String {
        let screen = TerminalScreenBuffer()
        let output = NSMutableAttributedString()
        for chunk in chunks {
            screen.consume(Data(chunk.utf8))
            if let patch = screen.takePatch() { output.replaceCharacters(in: patch.range, with: patch.text) }
        }
        return output.string
    }

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
            switch update.kind {
            case .append(let chunk), .replace(_, let chunk): appendLengths.append(chunk.length)
            case .reset: break
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
            TerminalRenderUpdate(revision: 2, kind: .replace(NSRange(location: 0, length: 5), NSAttributedString(string: "rewritten"))),
            fallbackSnapshot: { NSAttributedString(string: "unused") },
            in: textView
        )
        XCTAssertEqual(textView.string, "rewritten")

        coordinator.apply(
            TerminalRenderUpdate(revision: 4, kind: .append(NSAttributedString(string: "third"))),
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

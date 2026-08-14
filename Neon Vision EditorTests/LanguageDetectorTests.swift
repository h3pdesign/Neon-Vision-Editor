import XCTest
@testable import Neon_Vision_Editor



/// MARK: - Tests

@MainActor
final class LanguageDetectorTests: XCTestCase {
    func testPreferredLanguageForExtensions() {
        let cases: [(String, String)] = [
            ("main.swift", "swift"),
            ("main.ada", "ada"),
            ("main.adb", "ada"),
            ("main.ads", "ada"),
            ("main.py", "python"),
            ("main.ts", "typescript"),
            ("main.js", "javascript"),
            ("main.php", "php"),
            ("main.java", "java"),
            ("main.kt", "kotlin"),
            ("main.go", "go"),
            ("main.rb", "ruby"),
            ("main.rs", "rust"),
            ("main.c", "c"),
            ("main.cpp", "cpp"),
            ("main.h", "cpp"),
            ("main.m", "objective-c"),
            ("main.mm", "objective-c"),
            ("main.cs", "csharp"),
            ("main.json", "json"),
            ("events.ndjson", "json"),
            ("main.yml", "yaml"),
            ("main.toml", "toml"),
            ("flake.nix", "nix"),
            ("message.eml", "eml"),
            ("main.csv", "csv"),
            ("main.txt", "plain"),
            ("Example.crash", "crashlog"),
            ("Example.ips", "crashlog"),
            ("main.ini", "ini"),
            ("main.md", "markdown"),
            ("main.typ", "typst"),
            ("main.mdown", "markdown"),
            ("main.mkdn", "markdown"),
            ("main.mdx", "markdown"),
            ("main.proto", "proto"),
            ("main.graphql", "graphql"),
            ("main.rst", "rst"),
            ("main.conf", "nginx"),
            ("main.sh", "bash"),
            ("main.zsh", "zsh"),
            ("main.fish", "fish"),
            ("main.pl", "perl"),
            ("main.lua", "lua"),
            ("analysis.r", "r"),
            ("main.tf", "hcl"),
            ("settings.xcconfig", "xcconfig"),
            ("Localizable.strings", "strings"),
            ("component.jsx", "javascript"),
            ("main.ps1", "powershell"),
            ("main.ipynb", "ipynb"),
            ("Package.resolved", "json"),
            ("Dockerfile", "dockerfile"),
            ("Makefile", "makefile")
        ]

        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            let detected = LanguageDetector.shared.preferredLanguage(for: url)
            XCTAssertEqual(detected, expected, "Expected \(expected) for \(name), got \(String(describing: detected))")
        }
    }

    func testPreferredLanguageForDotfiles() {
        let cases: [(String, String)] = [
            (".zshrc", "zsh"),
            (".bashrc", "bash"),
            (".env", "dotenv"),
            (".gitconfig", "ini"),
            (".env.local", "dotenv")
        ]

        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            let detected = LanguageDetector.shared.preferredLanguage(for: url)
            XCTAssertEqual(detected, expected, "Expected \(expected) for \(name), got \(String(describing: detected))")
        }
    }

    func testDetectByContentSamples() {
        let cases: [(String, String)] = [
            ("import SwiftUI\n@main\nstruct App: App {\n var body: some Scene { WindowGroup { Text(\"Hi\") } } }", "swift"),
            ("def main():\n    print('hi')\n", "python"),
            ("function foo() { console.log('x'); }", "javascript"),
            ("interface User { id: string }\nconst x: number = 1", "typescript"),
            ("public class Main { public static void main(String[] args) {} }", "java"),
            ("fun main() { println(\"hi\") }", "kotlin"),
            ("package main\nimport \"fmt\"\nfunc main() { fmt.Println(\"hi\") }", "go"),
            ("def hello\n  puts 'hi'\nend", "ruby"),
            ("fn main() { let mut x = 1; }", "rust"),
            ("<?php echo 'hi';", "php"),
            ("syntax = \"proto3\";\nmessage Hello { string id = 1; }", "proto"),
            ("type Query { hello: String }", "graphql"),
            ("server { listen 80; location / { return 200; } }", "nginx"),
            (".. toctree::\n\n   intro", "rst"),
            ("KEY=VALUE\nOTHER_KEY=VALUE", "dotenv"),
            ("a,b,c\n1,2,3\n4,5,6", "csv"),
            ("#include <stdio.h>\nint main(void) { return 0; }", "c"),
            ("#include <iostream>\nint main() { std::cout << 1; }", "cpp"),
            ("#import <Foundation/Foundation.h>\n@interface Foo : NSObject\n@end", "objective-c"),
            ("SELECT * FROM users WHERE id = 1;", "sql"),
            ("<?xml version=\"1.0\"?><root><a>1</a></root>", "xml"),
            ("name: test\nvalue: 2", "yaml"),
            ("[section]\nkey = value", "toml"),
            ("{ pkgs ? import <nixpkgs> {} }:\npkgs.stdenv.mkDerivation { pname = \"demo\"; }", "nix"),
            ("From: sender@example.com\nTo: reader@example.com\nSubject: Hello\nMIME-Version: 1.0\nContent-Type: text/plain\n\nMessage body", "eml"),
            ("[section]\nkey=value", "ini"),
            ("set number\nsyntax on", "vim"),
            ("[INFO] app started", "log"),
            ("Param([string]$Name)\nWrite-Host $Name", "powershell"),
            ("IDENTIFICATION DIVISION.\nPROGRAM-ID. MAIN.", "cobol"),
            ("{\"cells\": [], \"metadata\": {}, \"cell_type\": \"code\"}", "ipynb"),
            ("#let title = [Typst]\n#show: document => document", "typst"),
            ("# Title\n\n- Item", "markdown"),
            ("{\"a\": 1, \"b\": 2}", "json"),
            ("using System;\nnamespace Foo { class Program { static void Main() {} } }", "csharp")
        ]

        for (text, expected) in cases {
            let result = LanguageDetector.shared.detect(text: text, name: nil, fileURL: nil)
            XCTAssertEqual(result.lang, expected, "Expected \(expected) for sample, got \(result.lang)")
        }
    }

    func testDetectPlainWhenNoSignal() {
        let result = LanguageDetector.shared.detect(text: "", name: nil, fileURL: nil)
        XCTAssertEqual(result.lang, "plain")
    }

    func testDetectsAppleCrashReportsSavedAsText() {
        let report = """
        Incident Identifier: 6156848E-344E-4D9E-84E0-87AFD0D0AE7B
        Process: TouchCanvas [1052]
        Exception Type: EXC_BAD_ACCESS (SIGSEGV)
        Crashed Thread: 0
        Thread 0 Crashed:
        0   TouchCanvas  0x0000000102afb3d0 update + 12
        Binary Images:
        0x102aec000 - 0x102b03fff TouchCanvas arm64
        """

        let result = Neon_Vision_Editor.LanguageDetector.shared.detect(text: report, name: "report.txt", fileURL: URL(fileURLWithPath: "/tmp/report.txt"))
        XCTAssertEqual(result.lang, "crashlog")
        XCTAssertTrue(Neon_Vision_Editor.AppleCrashReportParser.looksLikeAppleCrashReport(report))
        let sections = Neon_Vision_Editor.AppleCrashReportParser.sections(from: report)
        XCTAssertEqual(sections.map(\.title), ["Summary", "Crash Cause", "Threads", "Binary Images"])
        let causeEntries = sections.first(where: { $0.title == "Crash Cause" })?.entries ?? []
        XCTAssertTrue(causeEntries.allSatisfy { $0.severity == .critical })
    }

    func testDetectsTimestampedTextLogsWithoutMisclassifyingProse() {
        let log = """
        2026-07-20 10:32:01 INFO Started service
        2026-07-20 10:32:02 WARN Retrying request
        2026-07-20 10:32:03 ERROR Request failed
        """
        let prose = "The error budget is discussed in this ordinary text document."

        XCTAssertEqual(Neon_Vision_Editor.LanguageDetector.shared.detect(text: log, name: "session.txt", fileURL: URL(fileURLWithPath: "/tmp/session.txt")).lang, "log")
        XCTAssertEqual(Neon_Vision_Editor.LanguageDetector.shared.detect(text: prose, name: "notes.txt", fileURL: URL(fileURLWithPath: "/tmp/notes.txt")).lang, "plain")
    }

    func testStructuredLogParserGroupsCommonAndJSONLogFormats() {
        let log = """
        2026-07-25T10:31:00Z INFO Service started
        2026-07-25T10:31:01Z WARN Retrying request
        {"@timestamp":"2026-07-25T10:31:02Z","level":"error","message":"Request failed"}
        Jul 25 10:31:03 host process[42]: connection closed
        """

        let snapshot = StructuredLogParser.snapshot(from: log)

        XCTAssertEqual(snapshot.totalEntries, 4)
        XCTAssertEqual(snapshot.displayedEntries, 4)
        XCTAssertEqual(snapshot.sections.first(where: { $0.severity == .error })?.entries.first?.message, "Request failed")
        XCTAssertEqual(snapshot.sections.first(where: { $0.severity == .warning })?.entries.count, 1)
        XCTAssertEqual(snapshot.sections.first(where: { $0.severity == .info })?.entries.count, 1)
        XCTAssertEqual(snapshot.sections.first(where: { $0.severity == .other })?.entries.count, 1)
    }

    func testParsesTwoObjectIPSCrashReports() {
        let metadata = #"{"bug_type":"309","name":"ExampleApp","incident_id":"A1"}"#
        let report = #"{"incident":"A1","procName":"ExampleApp","exception":{"type":"EXC_CRASH","codes":"0x0"},"termination":{"reason":"SIGNAL 6"},"faultingThread":0,"threads":[{"id":0,"triggered":true,"queue":"com.apple.main-thread"}],"usedImages":[{"name":"ExampleApp"}]}"#
        let text = metadata + "\n" + report

        let sections = Neon_Vision_Editor.AppleCrashReportParser.sections(from: text)
        XCTAssertTrue(Neon_Vision_Editor.AppleCrashReportParser.looksLikeAppleCrashReport(text))
        XCTAssertEqual(sections.map(\.title), ["Summary", "Crash Cause", "Threads", "Binary Images"])
    }

    func testMarkdownExtensionNotOverriddenBySQLHeuristics() {
        let text = """
        # History vision

        Concrete API plan:
        SELECT endpoint, method FROM api_catalog WHERE active = 1;
        """
        let url = URL(fileURLWithPath: "/tmp/History vision Concrete API plan.md")
        let result = LanguageDetector.shared.detect(text: text, name: url.lastPathComponent, fileURL: url)
        XCTAssertEqual(result.lang, "markdown")
    }

    func testMarkdownStructureDetectionBeyondHeadings() {
        let samples = [
            """
            - [x] Done
            - [ ] Next
            """,
            """
            | Name | Value |
            | --- | ---: |
            | alpha | 1 |
            """,
            """
            [docs]: https://example.com/docs

            Use the reference link above.
            """,
            """
            ---
            title: Notes
            ---

            # Notes
            """
        ]

        for sample in samples {
            let result = LanguageDetector.shared.detect(text: sample, name: nil, fileURL: nil)
            XCTAssertEqual(result.lang, "markdown", "Expected markdown for sample, got \(result.lang)")
        }
    }

    func testCommentSyntaxDoesNotBecomeMarkdown() {
        let samples: [(String, String, String)] = [
            (
                "# Configuration\ndef main():\n    # Run the query\n    return \"ok\"",
                "python",
                "Python comments must not be treated as Markdown headings"
            ),
            (
                "#!/bin/bash\n# Build configuration\nset -e\necho done",
                "bash",
                "Shell comments must not be treated as Markdown headings"
            ),
            (
                "# Service configuration\nname: example\nport: 8080",
                "yaml",
                "YAML comments must not be treated as Markdown headings"
            )
        ]

        for (sample, expected, message) in samples {
            XCTAssertEqual(
                LanguageDetector.shared.detect(text: sample, name: nil, fileURL: nil).lang,
                expected,
                message
            )
        }

        XCTAssertFalse(LanguageDetector.shared.isStrongMarkdown(text: "# Configuration\n# Run the query"))
        XCTAssertTrue(LanguageDetector.shared.isStrongMarkdown(text: "# Notes\n\nThis is a Markdown paragraph."))
        XCTAssertTrue(LanguageDetector.shared.isStrongMarkdown(text: "# Notes\n\n- First item"))
    }
}

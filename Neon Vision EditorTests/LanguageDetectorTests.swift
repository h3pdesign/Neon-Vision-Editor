import XCTest



/// MARK: - Tests

final class LanguageDetectorTests: XCTestCase {
    func testPreferredLanguageForExtensions() {
        let cases: [(String, String)] = [
            ("main.swift", "swift"),
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
            ("main.yml", "yaml"),
            ("main.toml", "toml"),
            ("main.csv", "csv"),
            ("main.txt", "plain"),
            ("main.ini", "ini"),
            ("main.md", "markdown"),
            ("main.proto", "proto"),
            ("main.graphql", "graphql"),
            ("main.rst", "rst"),
            ("main.conf", "nginx"),
            ("main.sh", "bash"),
            ("main.zsh", "zsh"),
            ("main.ps1", "powershell"),
            ("main.ipynb", "ipynb")
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
            ("[section]\nkey=value", "ini"),
            ("set number\nsyntax on", "vim"),
            ("[INFO] app started", "log"),
            ("Param([string]$Name)\nWrite-Host $Name", "powershell"),
            ("IDENTIFICATION DIVISION.\nPROGRAM-ID. MAIN.", "cobol"),
            ("{\"cells\": [], \"metadata\": {}, \"cell_type\": \"code\"}", "ipynb"),
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
}

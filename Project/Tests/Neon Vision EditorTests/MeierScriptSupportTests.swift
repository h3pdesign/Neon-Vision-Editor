import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class MeierScriptSupportTests: XCTestCase {
    private let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)

    func testSyntaxCheckDiagnosticsAreShiftedBackToEditorLines() {
        let source = "print(1)\nvar x = \nif {\n"
        XCTAssertEqual(
            MeierScriptLanguage.remapSyntaxCheckDiagnostics("Parser error at 4:1: Unexpected token in expression. Found: kwIf\n", source: source),
            "Parser error at 3:1: Unexpected token in expression. Found: kwIf\n"
        )
        XCTAssertEqual(MeierScriptLanguage.remapSyntaxCheckDiagnostics("Lexer error: Unexpected character '#' at 1:1", source: source),
                       "Lexer error: Unexpected character '#' at 1:1")
        XCTAssertEqual(MeierScriptLanguage.remapDiagnostics("Runtime error: boom", source: source), "Runtime error: boom")
        XCTAssertTrue(MeierScriptLanguage.syntaxCheckSource(for: "print(1)").hasPrefix("exit()\n"))
    }

    /// The CLI drops staticLet statements (and their \"\"\" blocks) before
    /// counting lines, so its positions must be mapped back to the editor.
    func testDiagnosticsSkipLinesTheCLIRemovesForStaticLet() {
        let source = "print(0)\nstaticLet a = \"x\"\nstaticLet t = \"\"\"\none\ntwo\n\"\"\"\nprint(2\nvar x = 1\n"
        XCTAssertEqual(MeierScriptLanguage.parsedLineMap(for: source), [1, 7, 8])
        XCTAssertEqual(MeierScriptLanguage.remapDiagnostics("Parser error at 3:1: Expected rParen", source: source),
                       "Parser error at 8:1: Expected rParen")
        XCTAssertEqual(MeierScriptLanguage.remapDiagnostics("Parser error at 4:1: x", source: source, preludeLineCount: 1),
                       "Parser error at 8:1: x")
        XCTAssertEqual(MeierScriptLanguage.remapDiagnostics("Parser error at 5:1: Found: eof", source: source),
                       "Parser error at 10:1: Found: eof")
    }

    func testFirstDiagnosticReadsLineAndColumn() {
        let parser = MeierScriptLanguage.firstDiagnostic(in: "Parser error at 2:7: Unexpected token. Found: eof\n")
        XCTAssertEqual(parser?.line, 2)
        XCTAssertEqual(parser?.column, 7)
        XCTAssertEqual(parser?.message, "Parser error Unexpected token. Found: eof")
        XCTAssertEqual(MeierScriptLanguage.firstDiagnostic(in: "Lexer error: Unexpected character '#' at 5:1")?.line, 5)
        XCTAssertNil(MeierScriptLanguage.firstDiagnostic(in: "Runtime error: boom"))
        XCTAssertNil(MeierScriptLanguage.firstDiagnostic(in: ""))
    }

    func testVocabularyCompletionListsKeywordsBuiltinsAndDocumentNames() {
        let builtin = CompletionHeuristics.vocabularySuffixes(in: "pri" as NSString, caretLocation: 3, language: "meierscript")
        XCTAssertEqual(builtin.prefix, "pri")
        XCTAssertEqual(builtin.suffixes, ["nt", "ntError"])

        let keyword = CompletionHeuristics.vocabularySuffixes(in: "stat" as NSString, caretLocation: 4, language: "meierscript")
        XCTAssertEqual(keyword.suffixes.first, "icLet")

        let text = "func handleError(error: String) -> Bool { return true }\nhandl" as NSString
        let document = CompletionHeuristics.vocabularySuffixes(in: text, caretLocation: text.length, language: "meierscript")
        XCTAssertEqual(document.suffixes, ["eError"])
    }

    func testVocabularyCompletionStaysQuietInCommentsStringsAndShortPrefixes() {
        for sample in ["// pri", "print(\"pri", "p", "1pr"] {
            let text = sample as NSString
            XCTAssertTrue(CompletionHeuristics.vocabularySuffixes(in: text, caretLocation: text.length,
                                                                  language: "meierscript").suffixes.isEmpty, sample)
        }
        XCTAssertTrue(CompletionHeuristics.usesLocalVocabularyCompletion(for: "MeierScript"))
        XCTAssertFalse(CompletionHeuristics.usesLocalVocabularyCompletion(for: "swift"))
    }

    func testHighlightingColorsKeywordsBuiltinsStringsAndComments() {
        let patterns = getSyntaxPatterns(for: "meierscript", colors: colors)
        let sample = "staticLet title = \"Hi\" // note\nprint(„de“, ERRORCODE, nil)"
        func ranges(for color: Color) -> [String] {
            patterns.filter { $0.value == color }.flatMap { pattern, _ -> [String] in
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                    XCTFail("Invalid pattern \(pattern)"); return []
                }
                let ns = sample as NSString
                return regex.matches(in: sample, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
            }
        }
        XCTAssertTrue(ranges(for: colors.keyword).contains("staticLet"))
        XCTAssertTrue(ranges(for: colors.builtin).contains("print"))
        XCTAssertTrue(ranges(for: colors.string).contains("\"Hi\""))
        XCTAssertTrue(ranges(for: colors.string).contains("„de“"))
        XCTAssertTrue(ranges(for: colors.comment).contains("// note"))
        XCTAssertTrue(ranges(for: colors.variable).contains("ERRORCODE"))
        XCTAssertTrue(ranges(for: colors.atom).contains("nil"))
    }

    /// The Mac editor colors one line at a time, so a string or block comment
    /// still open at a line break must carry over to the following lines.
    func testLiteralScannerCarriesMultiLineStringsAndCommentsAcrossLines() throws {
        let scanner = try XCTUnwrap(SyntaxLiteralScanner.forLanguage("meierscript"))
        let lines = [
            #"staticLet banner = """"#,
            "Welcome to the demo.",
            #"""" // done"#,
            #"/* Functions for "x""#,
            #"   and nil */ print("say \"hi\"", „Herr Meier“) // 1. true"#
        ]
        var state: SyntaxLiteralScanner.State = nil
        let found = lines.map { line -> [String] in
            let ns = line as NSString
            return scanner.literals(in: ns, range: NSRange(location: 0, length: ns.length), state: &state)
                .map { ($0.isComment ? "C:" : "S:") + ns.substring(with: $0.range) }
        }
        XCTAssertEqual(found[0], [#"S:""""#])
        XCTAssertEqual(found[1], ["S:Welcome to the demo."])
        XCTAssertEqual(found[2], [#"S:""""#, "C:// done"])
        XCTAssertEqual(found[3], [#"C:/* Functions for "x""#])
        XCTAssertEqual(found[4], ["C:   and nil */", #"S:"say \"hi\"""#, "S:„Herr Meier“", "C:// 1. true"])
        XCTAssertNil(state)
        XCTAssertTrue(scanner.masksInnerTokens)

        let url = #"let url = "https://example.com" // note"# as NSString
        XCTAssertEqual(scanner.literals(in: url, range: NSRange(location: 0, length: url.length), state: &state)
            .map { url.substring(with: $0.range) }, [#""https://example.com""#, "// note"])
    }

    /// Swift and Python only report multi-line strings; their other strings and
    /// comments stay with the regex patterns.
    func testLiteralScannerReportsOnlyTripleQuotedStringsForOtherLanguages() throws {
        let python = try XCTUnwrap(SyntaxLiteralScanner.forLanguage("py"))
        XCTAssertFalse(python.masksInnerTokens)
        var state: SyntaxLiteralScanner.State = nil
        let doc = "x = 'a'  # '''\ndef f():\n    '''Return the value.\n    \"\"\" stays inside\n    '''\n" as NSString
        let literals = python.literals(in: doc, range: NSRange(location: 0, length: doc.length), state: &state)
        XCTAssertEqual(literals.map { doc.substring(with: $0.range) }, ["'''Return the value.\n    \"\"\" stays inside\n    '''"])
        XCTAssertNil(state)

        let swift = try XCTUnwrap(SyntaxLiteralScanner.forLanguage("swift"))
        let open = "let s = \"\"\"" as NSString
        XCTAssertEqual(swift.literals(in: open, range: NSRange(location: 0, length: open.length), state: &state).count, 1)
        XCTAssertEqual(state, "\"\"\"")
        XCTAssertNil(SyntaxLiteralScanner.forLanguage("javascript"))

        // A """ inside a Swift or Kotlin block comment opens nothing, and the
        // comment itself stays with the regex patterns.
        for language in ["swift", "kotlin"] {
            let scanner = try XCTUnwrap(SyntaxLiteralScanner.forLanguage(language))
            var commentState: SyntaxLiteralScanner.State = nil
            for line in [#"/* Example delimiter: """"#, #"*/ let count = 42"#] {
                let ns = line as NSString
                XCTAssertEqual(scanner.literals(in: ns, range: NSRange(location: 0, length: ns.length), state: &commentState), [], language)
            }
            XCTAssertNil(commentState, language)
        }

        // TOML literal strings and Kotlin raw strings have no escapes.
        let toml = try XCTUnwrap(SyntaxLiteralScanner.forLanguage("toml"))
        var tomlState: SyntaxLiteralScanner.State = nil
        let path = #"path = '''C:\'''"# as NSString
        XCTAssertEqual(toml.literals(in: path, range: NSRange(location: 0, length: path.length), state: &tomlState).count, 1)
        XCTAssertNil(tomlState)
        let kotlin = try XCTUnwrap(SyntaxLiteralScanner.forLanguage("kotlin"))
        let raw = #"val p = """C:\""""# as NSString
        XCTAssertEqual(kotlin.literals(in: raw, range: NSRange(location: 0, length: raw.length), state: &tomlState).count, 1)
        XCTAssertNil(tomlState)
    }

    func testLanguageIsRegistered() {
        XCTAssertTrue(CodeTemplateCatalog.supportedLanguages.contains("meierscript"))
        XCTAssertNotNil(CodeTemplateCatalog.defaultTemplate(for: "meierscript"))
        XCTAssertEqual(LanguageDetector.shared.preferredLanguage(for: URL(fileURLWithPath: "/tmp/Test.meierscript")), "meierscript")
        XCTAssertTrue(EditorLoadHelper.supportedTextExtensions.contains("meierscript"))
        XCTAssertTrue(isViewportSafeSyntaxLanguage("meierscript"))
    }

#if os(macOS)
    func testCandidateHostAppsKeepRegisteredAppsFirstWithoutDuplicates() {
        let registered = URL(fileURLWithPath: "/Users/test/Applications/SidUI Editor.app", isDirectory: true)
        let known = URL(fileURLWithPath: "/Applications/SidUI Editor.app", isDirectory: true)
        let candidates = MeierScriptRunner.candidateHostApps(registered: [registered, known])
        XCTAssertEqual(candidates.first, registered)
        XCTAssertEqual(candidates.filter { $0.path == known.path }.count, 1)
        XCTAssertEqual(candidates.count, MeierScriptRunner.knownHostAppPaths.count + 1)
    }

    /// Exercises the installed CLI end to end; skipped where SidUI is absent.
    func testInstalledCLIRunsSeparatesStreamsAndChecksWithoutExecuting() async throws {
        guard let cli = MeierScriptRunner.locateCLI() else { throw XCTSkip("meierscript CLI not installed") }

        let run = await MeierScriptRunner.execute(source: "print(\"out\")\nprintError(\"err\")\n", mode: .run,
                                                  cliURL: cli, workingDirectory: nil, timeout: 10)
        XCTAssertEqual(run.exitCode, 0)
        XCTAssertEqual(run.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertTrue(run.standardError.contains("err"))

        let check = await MeierScriptRunner.execute(source: "print(\"ran\")\nvar x = \nif {\n", mode: .syntaxCheck,
                                                    cliURL: cli, workingDirectory: nil, timeout: 10)
        XCTAssertNotEqual(check.exitCode, 0)
        XCTAssertEqual(check.standardOutput, "")
        XCTAssertEqual(MeierScriptLanguage.firstDiagnostic(in: check.standardError)?.line, 3)

        let valid = await MeierScriptRunner.execute(source: "print(\"ran\")\n", mode: .syntaxCheck,
                                                    cliURL: cli, workingDirectory: nil, timeout: 10)
        XCTAssertEqual(valid.exitCode, 0)
        XCTAssertEqual(valid.standardOutput, "", "A syntax check must not execute the script")

        // The sample scripts shipped in ScriptingSDKit must pass the check
        // without running (they touch system information and preferences).
        let documentation = cli.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Frameworks/ScriptingSDKit.framework/Versions/A/Resources/Documentation")
        for name in ["Test.meierscript", "Test2.meierscript"] {
            let url = documentation.appendingPathComponent(name)
            guard let sample = try? String(contentsOf: url, encoding: .utf8) else { XCTFail("Unreadable \(url.path)"); continue }
            let sampleCheck = await MeierScriptRunner.execute(source: sample, mode: .syntaxCheck,
                                                              cliURL: cli, workingDirectory: nil, timeout: 10)
            XCTAssertEqual(sampleCheck.exitCode, 0, "\(name): \(sampleCheck.standardError)")
            XCTAssertEqual(sampleCheck.standardOutput, "", name)
            XCTAssertFalse(MeierScriptLanguage.firstDiagnostic(in: sampleCheck.standardError) != nil, name)
        }

        let staticSource = "staticLet a = \"x\"\nstaticLet t = \"\"\"\none\n\"\"\"\nprint(2\nvar x = 1\n"
        for mode in [MeierScriptRunner.Mode.syntaxCheck, .run] {
            let mapped = await MeierScriptRunner.execute(source: staticSource, mode: mode,
                                                         cliURL: cli, workingDirectory: nil, timeout: 10)
            XCTAssertEqual(MeierScriptLanguage.firstDiagnostic(in: mapped.standardError)?.line, 6, mapped.standardError)
        }

        let endless = await MeierScriptRunner.execute(source: "while true { }\n", mode: .run,
                                                      cliURL: cli, workingDirectory: nil, timeout: 1)
        XCTAssertTrue(endless.timedOut)
        XCTAssertLessThan(endless.duration, 5)
    }
#endif

    func testFunctionCompletionInsertsCallWithRequiredParameters() {
        func suffixes(_ sample: String) -> [String] {
            let text = sample as NSString
            return CompletionHeuristics.vocabularySuffixes(in: text, caretLocation: text.length, language: "meierscript",
                                                           insertsCallTemplates: true).suffixes
        }
        XCTAssertEqual(suffixes("pri"), ["nt(string)", "ntError(string)"])
        XCTAssertEqual(suffixes("getComm"), ["ands()"])
        XCTAssertEqual(suffixes("le").first, "t", "Keywords stay plain words")
        XCTAssertEqual(suffixes("func greet(name: String, times: Int) {}\ngre"), ["et(name, times)"])
        XCTAssertEqual(suffixes("func run() {}\nfunc ru"), ["nCommand", "n"], "Naming a function is not a call")
        XCTAssertEqual(CompletionHeuristics.vocabularySuffixes(in: "pri" as NSString, caretLocation: 3,
                                                               language: "swift", insertsCallTemplates: true).suffixes,
                       CompletionHeuristics.vocabularySuffixes(in: "pri" as NSString, caretLocation: 3, language: "swift").suffixes)
        for name in MeierScriptLanguage.builtins {
            XCTAssertNotNil(MeierScriptLanguage.callTemplate(forBuiltin: name), name)
        }
        XCTAssertNil(MeierScriptLanguage.callTemplate(forBuiltin: "let"))
    }

    func testCallArgumentPlaceholderRangeSelectsTheFirstArgument() {
        XCTAssertEqual(CompletionHeuristics.callArgumentPlaceholderRange(in: "print(string)"), NSRange(location: 6, length: 6))
        XCTAssertEqual(CompletionHeuristics.callArgumentPlaceholderRange(in: "split(string, separator)"), NSRange(location: 6, length: 6))
        XCTAssertEqual(CompletionHeuristics.callArgumentPlaceholderRange(in: "getCommands()"), NSRange(location: 13, length: 0))
        XCTAssertNil(CompletionHeuristics.callArgumentPlaceholderRange(in: "let"))
        XCTAssertNil(CompletionHeuristics.callArgumentPlaceholderRange(in: ")"))
    }
}

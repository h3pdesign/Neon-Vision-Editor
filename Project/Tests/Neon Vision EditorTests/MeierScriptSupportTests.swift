import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class MeierScriptSupportTests: XCTestCase {
    private let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)

    func testSyntaxCheckDiagnosticsAreShiftedBackToEditorLines() {
        XCTAssertEqual(
            MeierScriptLanguage.remapSyntaxCheckDiagnostics("Parser error at 4:1: Unexpected token in expression. Found: kwIf\n"),
            "Parser error at 3:1: Unexpected token in expression. Found: kwIf\n"
        )
        XCTAssertEqual(MeierScriptLanguage.remapSyntaxCheckDiagnostics("Lexer error: Unexpected character '#' at 1:1"),
                       "Lexer error: Unexpected character '#' at 1:1")
        XCTAssertEqual(MeierScriptLanguage.remapSyntaxCheckDiagnostics("Runtime error: boom"), "Runtime error: boom")
        XCTAssertTrue(MeierScriptLanguage.syntaxCheckSource(for: "print(1)").hasPrefix("exit()\n"))
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

        let endless = await MeierScriptRunner.execute(source: "while true { }\n", mode: .run,
                                                      cliURL: cli, workingDirectory: nil, timeout: 1)
        XCTAssertTrue(endless.timedOut)
        XCTAssertLessThan(endless.duration, 5)
    }
#endif
}

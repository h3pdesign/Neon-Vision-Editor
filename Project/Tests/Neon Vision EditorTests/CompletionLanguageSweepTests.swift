import XCTest
@testable import Neon_Vision_Editor

/// Exercises the completion gate for every language the editor offers:
/// code rows must stay eligible, comment rows must be skipped, and model
/// suggestions that use the language's own syntax must survive sanitizing.
@MainActor
final class CompletionLanguageSweepTests: XCTestCase {
    private static let proseLanguages: Set<String> = ["markdown", "plain", "rst"]

    /// A code row without a comment, ending where completion should run.
    private static let codeRows: [String: String] = [
        "swift": "let total = items.cou",
        "ada": "Put_Line (Item => Valu",
        "python": "result = values[len(items) // 2].lo",
        "javascript": "const total = items.reduce(sum, 0).toFi",
        "typescript": "const total: number = items.len",
        "php": "$total = count($ite",
        "java": "int total = items.siz",
        "kotlin": "val total = items.cou",
        "go": "total := len(item",
        "ruby": "total = \"#{count}\".len",
        "rust": "fn first<'a>(items: &'a [Item]) -> &'a Ite",
        "fish": "set -l total (count $ite",
        "perl": "my $total = scalar(@ite",
        "lua": "local total = #ite",
        "r": "total <- length(ite",
        "cobol": "MOVE WS-TOTAL TO WS-RES",
        "dotenv": "API_URL=https://example.com/v",
        "proto": "repeated Item ite",
        "graphql": "query { items { na",
        "rst": "The total is computed by the summ",
        "nginx": "proxy_pass http://backend:8080/ap",
        "sql": "SELECT name FROM users WHERE i",
        "html": "<a href=\"https://example.com\">Ho",
        "expressionengine": "{exp:channel:entries channel=\"news\"} {ti",
        "css": "background: url(https://example.com/a.png) no-rep",
        "c": "int total = count_ite",
        "cpp": "auto total = items.si",
        "dockerfile": "RUN curl -fsSL https://example.com/install.sh | ba",
        "makefile": "CFLAGS += -O2 -Wa",
        "hcl": "source = \"hashicorp/aws\"\n  versi",
        "xcconfig": "SWIFT_VERSION = 5.",
        "strings": "\"greeting\" = \"Hello\"; gree",
        "csharp": "var total = items.Cou",
        "objective-c": "NSInteger total = items.cou",
        "json": "{\"url\": \"https://example.com\", \"done\": tr",
        "xml": "<item href=\"https://example.com\">na",
        "yaml": "url: https://example.com/ap",
        "toml": "homepage = \"https://example.com\"\nvers",
        "nix": "buildInputs = [ pkgs.ope",
        "eml": "Link: https://example.com/inv",
        "csv": "https://example.com/a,https://example.com/b,na",
        "ini": "url = https://example.com/ap",
        "vim": "let g:total = len(ite",
        "log": "GET https://example.com/api 200 dura",
        "crashlog": "Thread 0 Crashed:: Dispatch queue: com.apple.main-thr",
        "ipynb": "{\"source\": [], \"execution_count\": nu",
        "markdown": "The total is computed by the summ",
        "typst": "It's computed by the #summ",
        "tex": "Don't forget the \\textbf{sum",
        "bash": "echo \"${#items[@]}\" && cou",
        "zsh": "print ${#items} && cou",
        "powershell": "$total = $items.Cou",
        "standard": "total = items.cou",
        "plain": "The total is computed by the summ"
    ]

    /// A row whose caret sits inside the language's line comment.
    private static let commentRows: [String: String] = [
        "swift": "let x = 1 // explain the val",
        "ada": "X := 1; -- explain the val",
        "python": "x = 1  # explain the val",
        "javascript": "let x = 1 // explain the val",
        "typescript": "let x = 1 // explain the val",
        "php": "$x = 1; # explain the val",
        "java": "int x = 1; // explain the val",
        "kotlin": "val x = 1 // explain the val",
        "go": "x := 1 // explain the val",
        "ruby": "x = 1 # explain the val",
        "rust": "let x = 1; // explain the val",
        "fish": "set x 1 # explain the val",
        "perl": "my $x = 1; # explain the val",
        "lua": "local x = 1 -- explain the val",
        "r": "x <- 1 # explain the val",
        "cobol": "MOVE 1 TO WS-X. *> explain the val",
        "dotenv": "# explain the val",
        "proto": "int32 x = 1; // explain the val",
        "graphql": "query { items } # explain the val",
        "nginx": "listen 80; # explain the val",
        "sql": "SELECT 1; -- explain the val",
        "html": "<!-- explain the val",
        "expressionengine": "{!-- explain the val",
        "c": "int x = 1; // explain the val",
        "cpp": "int x = 1; // explain the val",
        "dockerfile": "# explain the val",
        "makefile": "CFLAGS += -O2 # explain the val",
        "hcl": "count = 1 # explain the val",
        "xcconfig": "SWIFT_VERSION = 5.0 // explain the val",
        "strings": "// explain the val",
        "csharp": "var x = 1; // explain the val",
        "objective-c": "int x = 1; // explain the val",
        "xml": "<!-- explain the val",
        "yaml": "key: value # explain the val",
        "toml": "key = 1 # explain the val",
        "nix": "x = 1; # explain the val",
        "ini": "; explain the val",
        "vim": "\" explain the val",
        "typst": "// explain the val",
        "tex": "\\section{Intro} % explain the val",
        "bash": "x=1 # explain the val",
        "zsh": "x=1 # explain the val",
        "powershell": "$x = 1 # explain the val",
        "standard": "x = 1 // explain the val"
    ]

    /// A model suggestion written in the language's own syntax.
    private static let syntaxSuggestions: [String: (prefix: String, raw: String, expected: String)] = [
        "swift": ("", "@MainActor func load()", "@MainActor func load()"),
        "python": ("", "@property  # cached", "@property  # cached"),
        "php": ("", "$items->count()", "$items->count()"),
        "perl": ("", "$total = @items;", "$total = @items;"),
        "bash": ("", "echo \"$HOME/${name}\"", "echo \"$HOME/${name}\""),
        "c": ("", "#include <stdio.h>", "#include <stdio.h>"),
        "cpp": ("", "~Buffer() = default;", "~Buffer() = default;"),
        "css": ("", "color: #ff00aa;", "color: #ff00aa;"),
        "tex": ("\\sec", "\\section{Results}", "tion{Results}"),
        "typst": ("", "$ x^2 + y^2 $", "$ x^2 + y^2 $"),
        "rust": ("", "items.iter().map(|x| x ^ mask)", "items.iter().map(|x| x ^ mask)"),
        "java": ("", "@Override", "@Override")
    ]

    func testEverySupportedLanguageIsCovered() {
        let languages = Set(CodeTemplateCatalog.supportedLanguages)
        XCTAssertEqual(languages.subtracting(Self.codeRows.keys), [], "Add a code row for each new language")
        for language in languages where !Self.proseLanguages.contains(language) {
            XCTAssertFalse(CompletionHeuristics.usesNaturalLanguageCompletion(for: language), language)
        }
        for language in Self.proseLanguages {
            XCTAssertTrue(CompletionHeuristics.usesNaturalLanguageCompletion(for: language), language)
        }
    }

    func testCodeRowsStayEligibleInEveryLanguage() {
        for (language, row) in Self.codeRows.sorted(by: { $0.key < $1.key }) {
            let text = row as NSString
            XCTAssertFalse(
                CompletionHeuristics.isLikelyInCommentOrString(in: text, caretLocation: text.length, language: language),
                "\(language): \(row)"
            )
        }
    }

    func testCommentRowsAreSkippedInEveryLanguageWithLineComments() {
        for (language, row) in Self.commentRows.sorted(by: { $0.key < $1.key }) {
            let text = row as NSString
            XCTAssertTrue(
                CompletionHeuristics.isLikelyInCommentOrString(in: text, caretLocation: text.length, language: language),
                "\(language): \(row)"
            )
        }
    }

    func testOpenStringsAreStillSkipped() {
        let cases: [(String, String)] = [
            ("rust", "let s = \"hel"),
            ("rust", "let c = '"),
            ("bash", "echo 'hel"),
            ("typst", "#let s = \"hel"),
            ("vim", "echo \"hel"),
            ("sql", "SELECT 'hel")
        ]
        for (language, row) in cases {
            let text = row as NSString
            XCTAssertTrue(
                CompletionHeuristics.isLikelyInCommentOrString(in: text, caretLocation: text.length, language: language),
                "\(language): \(row)"
            )
        }
    }

    func testModelSuggestionsKeepLanguageSyntax() {
        for (language, sample) in Self.syntaxSuggestions.sorted(by: { $0.key < $1.key }) {
            XCTAssertEqual(
                CompletionHeuristics.sanitizeModelSuggestion(
                    sample.raw,
                    currentTokenPrefix: sample.prefix,
                    nextDocumentText: "",
                    maxLength: 40,
                    allowsNaturalLanguage: CompletionHeuristics.usesNaturalLanguageCompletion(for: language)
                ),
                sample.expected,
                language
            )
        }
    }

    func testCodeSuggestionsStillRejectMultilineAndControlOutput() {
        XCTAssertEqual(
            CompletionHeuristics.sanitizeModelSuggestion("count()\nreturn total", currentTokenPrefix: "", nextDocumentText: ""),
            "count()"
        )
        XCTAssertEqual(
            CompletionHeuristics.sanitizeModelSuggestion("count()\u{7}", currentTokenPrefix: "", nextDocumentText: ""),
            ""
        )
    }
}

import XCTest
import SwiftUI
@testable import Neon_Vision_Editor

@MainActor
final class SyntaxHighlightingRegressionTests: XCTestCase {
    private let colors = SyntaxColors.fromVibrantLightTheme(colorScheme: .dark)

    func testJSONPatternsMatchEscapedURLsAndNumbers() {
        let patterns = getSyntaxPatterns(for: "json", colors: colors)
        let sample = """
        {
          "url": "http:\\/\\/lan-dc-01v",
          "ntlm": 0,
          "enabled": true
        }
        """
        XCTAssertTrue(anySyntaxPatternMatches(sample, from: patterns))
        XCTAssertTrue(matchesRegex(sample, pattern: #"\"[^\"]+\"\s*:"#))
        XCTAssertTrue(matchesRegex(sample, pattern: #""([^"\\]|\\.)*""#))
        XCTAssertTrue(matchesRegex(sample, pattern: #"\b(-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?)\b"#))
    }

    func testMarkdownPatternsMatchTaskListsAndLinks() {
        let patterns = getSyntaxPatterns(for: "markdown", colors: colors)
        let sample = """
        - [x] Done
        - [ ] Todo
        [Docs](https://example.com)
        <!-- comment -->
        """
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^\s*[-*+]\s+\[[ xX]\]\s+.*$"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\[[^\]\n]+\]\([^)]+\)"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?s)<!--.*?-->"#))
    }

    func testHTMLAndCSSPatternsMatchTagsAndProperties() {
        let htmlPatterns = getSyntaxPatterns(for: "html", colors: colors)
        let cssPatterns = getSyntaxPatterns(for: "css", colors: colors)

        let htmlSample = #"<a href="https://example.com" class="btn">Open</a>"#
        let cssSample = """
        body {
          background-color: #ffaa33;
        }
        """

        XCTAssertTrue(anySyntaxPatternMatches(htmlSample, from: htmlPatterns))
        XCTAssertTrue(anySyntaxPatternMatches(cssSample, from: cssPatterns))
        XCTAssertTrue(matchesRegex(htmlSample, pattern: #"</?[A-Za-z][A-Za-z0-9:-]*"#))
        XCTAssertTrue(matchesRegex(htmlSample, pattern: #"\b[A-Za-z_:][A-Za-z0-9_:.-]*(?=\s*=)"#))
        XCTAssertTrue(matchesRegex(htmlSample, pattern: #""[^"\n]*"|'[^'\n]*'"#))
        XCTAssertTrue(matchesRegex(cssSample, pattern: #"\b([a-zA-Z-]+)\s*:"#))
        XCTAssertTrue(matchesRegex(cssSample, pattern: #"#[0-9A-Fa-f]{3,6}\b"#))
    }

    func testHTMLFastRangesRemainValidDuringIncompleteEdit() {
        // Typing often leaves a tag or attribute quote temporarily incomplete.
        let sample = "<section class=\"card\">\n  <a href=\"https://example.com"
        let text = sample as NSString
        let ranges = fastSyntaxColorRanges(
            language: "html",
            profile: .htmlFast,
            text: text,
            in: NSRange(location: 0, length: text.length),
            colors: colors
        )

        XCTAssertNotNil(ranges)
        XCTAssertFalse(ranges?.isEmpty ?? true)
        XCTAssertTrue((ranges ?? []).allSatisfy { isValidRange($0.0, utf16Length: text.length) })
    }

    func testHTMLFastRangesPreserveExtendedSyntaxTokens() {
        let sample = #"<section class="card" data-state=open>&amp;</section>"#
        let text = sample as NSString
        let ranges = fastSyntaxColorRanges(
            language: "html",
            profile: .htmlFast,
            text: text,
            in: NSRange(location: 0, length: text.length),
            colors: colors
        ) ?? []
        let tokens = Set(ranges.map { text.substring(with: $0.0) })

        XCTAssertTrue(tokens.contains("class"))
        XCTAssertTrue(tokens.contains(#""card""#))
        XCTAssertTrue(tokens.contains("data-state"))
        XCTAssertTrue(tokens.contains("open"))
        XCTAssertTrue(tokens.contains("&amp;"))
    }

    func testHTMLStyleBlocksReceiveCSSSyntaxColors() {
        let sample = """
        <style>
        .logo-mark {
          --accent: #64b2ba;
          background: linear-gradient(135deg, rgba(100, 178, 186, 0.18), #efbe4d);
        }
        </style>
        """
        let text = sample as NSString
        let ranges = fastHTMLSyntaxColorRanges(
            text: text,
            in: NSRange(location: 0, length: text.length),
            colors: colors
        )
        let tokens = Set(ranges.map { text.substring(with: $0.0) })

        XCTAssertTrue(tokens.contains(".logo-mark"))
        XCTAssertTrue(tokens.contains("--accent"))
        XCTAssertTrue(tokens.contains("#64b2ba"))
        XCTAssertTrue(tokens.contains("linear-gradient("))
        XCTAssertTrue(tokens.contains("135deg"))
    }

    func testCSVKeepsResponsiveVisibleRangePolicyAndRespectsTokenBudget() {
        let defaults = UserDefaults.standard
        let syntaxModeKey = "SettingsLargeFileSyntaxHighlighting"
        let openModeKey = "SettingsLargeFileOpenMode"
        let previousSyntaxMode = defaults.object(forKey: syntaxModeKey)
        let previousOpenMode = defaults.object(forKey: openModeKey)
        defer {
            if let previousSyntaxMode {
                defaults.set(previousSyntaxMode, forKey: syntaxModeKey)
            } else {
                defaults.removeObject(forKey: syntaxModeKey)
            }
            if let previousOpenMode {
                defaults.set(previousOpenMode, forKey: openModeKey)
            } else {
                defaults.removeObject(forKey: openModeKey)
            }
        }
        defaults.set("minimal", forKey: syntaxModeKey)
        defaults.set("deferred", forKey: openModeKey)

        let text = NSString(string: String(repeating: "one,\"two\",three,four\n", count: 150_000))
        XCTAssertTrue(
            supportsResponsiveLargeFileHighlight(language: "csv", textLength: text.length),
            "CSV should retain responsive highlighting in minimal/deferred mode."
        )
        let ranges = fastSyntaxColorRanges(
            language: "csv",
            profile: .csvFast,
            text: text,
            in: NSRange(location: 0, length: min(text.length, 100_000)),
            colors: colors
        ) ?? []
        XCTAssertTrue(ranges.allSatisfy { isValidRange($0.0, utf16Length: text.length) }, "CSV ranges must remain in bounds.")

        let sample = NSString(string: "one,\"two\",three\n")
        let sampleRanges = fastSyntaxColorRanges(
            language: "csv",
            profile: .csvFast,
            text: sample,
            in: NSRange(location: 0, length: sample.length),
            colors: colors
        ) ?? []
        XCTAssertFalse(sampleRanges.isEmpty, "A small quoted CSV sample should produce syntax ranges.")
    }

    func testGeneratedAndMinifiedFilesRespectAutomaticAndExplicitOverrides() {
        let defaults = UserDefaults.standard
        let key = "SettingsGeneratedFileSyntaxHighlighting"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let minified = NSString(string: "/* @generated */" + String(repeating: "const value=1;", count: 8_000))
        let formatted = NSString(string: String(repeating: "const value = 1;\n", count: 8_000))
        XCTAssertTrue(isLikelyGeneratedOrMinifiedSyntaxText(minified))
        XCTAssertFalse(isLikelyGeneratedOrMinifiedSyntaxText(formatted))

        defaults.set("automatic", forKey: key)
        XCTAssertTrue(shouldSuppressGeneratedFileSyntaxHighlighting(text: minified, language: "javascript"))
        defaults.set("full", forKey: key)
        XCTAssertFalse(shouldSuppressGeneratedFileSyntaxHighlighting(text: minified, language: "javascript"))
        defaults.set("off", forKey: key)
        XCTAssertTrue(shouldSuppressGeneratedFileSyntaxHighlighting(text: minified, language: "javascript"))
    }

    func testNewProjectAndInfrastructureSyntaxesHavePatterns() {
        let samples: [(String, String)] = [
            ("dockerfile", "FROM swift:6.0\nRUN swift build"),
            ("makefile", "build: \n\tswift build"),
            ("hcl", "resource \"aws_s3_bucket\" \"assets\" {\n  force_destroy = true\n}"),
            ("fish", "function greet\n  echo hello\nend"),
            ("perl", "sub greet { return 1; }"),
            ("lua", "local value = 1 -- sample"),
            ("r", "function(value) { return(value) }"),
            ("xcconfig", "PRODUCT_BUNDLE_IDENTIFIER = $(PRODUCT_NAME)"),
            ("strings", "\"Welcome\" = \"Welcome\";")
        ]
        for (language, sample) in samples {
            XCTAssertTrue(anySyntaxPatternMatches(sample, from: getSyntaxPatterns(for: language, colors: colors)), language)
        }
    }

    func testLargeSVGKeepsResponsiveVisibleRangePolicy() {
        let defaults = UserDefaults.standard
        let syntaxModeKey = "SettingsLargeFileSyntaxHighlighting"
        let openModeKey = "SettingsLargeFileOpenMode"
        let previousSyntaxMode = defaults.object(forKey: syntaxModeKey)
        let previousOpenMode = defaults.object(forKey: openModeKey)
        defer {
            if let previousSyntaxMode { defaults.set(previousSyntaxMode, forKey: syntaxModeKey) }
            else { defaults.removeObject(forKey: syntaxModeKey) }
            if let previousOpenMode { defaults.set(previousOpenMode, forKey: openModeKey) }
            else { defaults.removeObject(forKey: openModeKey) }
        }
        defaults.set("minimal", forKey: syntaxModeKey)
        defaults.set("deferred", forKey: openModeKey)

        XCTAssertTrue(isXMLLikeSyntaxLanguage("svg"))
        XCTAssertTrue(
            supportsResponsiveLargeFileHighlight(language: "svg", textLength: 4_000_000),
            "A 40 MB SVG should use bounded visible-range highlighting rather than lose all coloring."
        )
        XCTAssertTrue(supportsViewportSyntaxHighlighting(language: "svg", textLength: 4_000_000))
        XCTAssertFalse(supportsResponsiveLargeFileHighlight(language: "svg", textLength: 9_000_000))
    }

    func testLargeHTMLKeepsResponsiveVisibleRangePolicy() {
        XCTAssertGreaterThan(
            EditorRuntimeLimits.htmlResponsiveSyntaxUTF16Length,
            EditorRuntimeLimits.syntaxMinimalUTF16Length
        )
        XCTAssertLessThanOrEqual(
            5_000_000,
            EditorRuntimeLimits.htmlResponsiveSyntaxUTF16Length,
            "A 5 MB HTML document should remain eligible for the bounded HTML scanner."
        )
    }

    func testProgrammingDocumentsUseViewportHighlightingAboveBudget() {
        let defaults = UserDefaults.standard
        let key = "SettingsLargeFileOpenMode"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set("deferred", forKey: key)
        XCTAssertFalse(supportsViewportSyntaxHighlighting(language: "swift", textLength: 399_999))
        XCTAssertTrue(supportsViewportSyntaxHighlighting(language: "swift", textLength: 400_000))
        XCTAssertFalse(supportsViewportSyntaxHighlighting(language: "markdown", textLength: 400_000))

        defaults.set("plainText", forKey: key)
        XCTAssertFalse(supportsViewportSyntaxHighlighting(language: "swift", textLength: 400_000))
    }

    func testXHTMLUsesHTMLSyntaxProfiles() {
        let regularPatterns = getSyntaxPatterns(for: "xhtml", colors: colors)
        let largeText = NSString(string: String(repeating: "<div></div>", count: 25_000))

        XCTAssertTrue(anySyntaxPatternMatches(#"<main class="content">Text</main>"#, from: regularPatterns))
        XCTAssertEqual(syntaxProfile(for: "xhtml", text: largeText), .htmlFast)
    }

    func testSwiftVisibleRangeHighlightingPerformance() {
        let source = String(repeating: "func render(value: Int) -> String { // visible pass\n    return \"value: \\(value)\"\n}\n", count: 2_000)
        let visibleRange = NSRange(location: 0, length: min((source as NSString).length, 12_000))
        let patterns = getSyntaxPatterns(for: "swift", colors: colors)

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()]) {
            var matchCount = 0
            for pattern in patterns.keys {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                matchCount += regex.numberOfMatches(in: source, options: [], range: visibleRange)
            }
            XCTAssertGreaterThan(matchCount, 0)
        }
    }

    func testCandCSharpPatternsMatchCommentsTypesAndKeywords() {
        let cPatterns = getSyntaxPatterns(for: "c", colors: colors)
        let csharpPatterns = getSyntaxPatterns(for: "csharp", colors: colors)

        let cSample = """
        // comment
        int main(void) { return 0; }
        """
        let csharpSample = """
        using System;
        namespace Demo {
          class Program {
            static void Main() { Console.WriteLine("ok"); }
          }
        }
        """

        XCTAssertTrue(matchesAnyPattern(in: cSample, from: cPatterns, expected: #"//.*|/\*([^*]|(\*+[^*/]))*\*+/"#))
        XCTAssertTrue(matchesAnyPattern(in: cSample, from: cPatterns, expected: #"\b(int|float|double|char|void|if|else|for|while|do|switch|case|return)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: csharpSample, from: csharpPatterns, expected: #"\b(class|interface|enum|struct|namespace|using|public|private|protected|internal|static|readonly|sealed|abstract|virtual|override|async|await|new|return|if|else|for|foreach|while|do|switch|case|break|continue|try|catch|finally|throw)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: csharpSample, from: csharpPatterns, expected: #"\b(string|int|double|float|bool|decimal|char|void|object|var|List<[^>]+>|Dictionary<[^>]+>)\b"#))
    }

    func testNixEmailAndTOMLPatternsCoverNativeConstructs() {
        let nixPatterns = getSyntaxPatterns(for: "nix", colors: colors)
        let emailPatterns = getSyntaxPatterns(for: "eml", colors: colors)
        let tomlPatterns = getSyntaxPatterns(for: "toml", colors: colors)
        let nix = """
        { pkgs ? import <nixpkgs> {} }:
        let version = "1.0"; in pkgs.stdenv.mkDerivation {
          pname = "demo";
          inherit version;
          src = ./.;
        }
        """
        let email = """
        From: Sender <sender@example.com>
        To: reader@example.com
        Subject: Build result
        Content-Type: multipart/alternative; boundary="sample"

        --sample
        > quoted reply
        """
        let toml = #"""
        [package.metadata.release]
        published-at = 2026-07-25T10:30:00Z
        checksum = 0xFF_A0
        targets = ["macOS", "iOS"]
        description = """A multiline
        value"""
        """#

        XCTAssertTrue(matchesRegex(nix, pattern: #"\b(assert|else|if|in|inherit|let|or|rec|then|with)\b"#), "Nix keywords")
        XCTAssertTrue(matchesRegex(nix, pattern: #"(?:\.{0,2}/|/)[^\s;)}\]]+|<[^>\n]+>"#), "Nix paths")
        XCTAssertTrue(anySyntaxPatternMatches(nix, from: nixPatterns), "Nix syntax map")
        XCTAssertTrue(matchesRegex(email, pattern: #"(?mi)^(from|to|cc|bcc|subject|date|message-id|in-reply-to|references|reply-to|sender|mime-version|content-type|content-transfer-encoding|content-disposition|received|return-path|delivered-to|authentication-results|dkim-signature):"#), "Email headers")
        XCTAssertTrue(matchesRegex(email, pattern: #"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#), "Email addresses")
        XCTAssertTrue(anySyntaxPatternMatches(email, from: emailPatterns), "Email syntax map")
        XCTAssertTrue(matchesRegex(toml, pattern: #"\b\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})?)?\b|\b\d{2}:\d{2}:\d{2}(?:\.\d+)?\b"#), "TOML date")
        XCTAssertTrue(anySyntaxPatternMatches(toml, from: tomlPatterns), "TOML syntax map")
    }

    func testSwiftAndPythonPatternsMatchModernConstructs() {
        let swiftPatterns = getSyntaxPatterns(for: "swift", colors: colors)
        let pythonPatterns = getSyntaxPatterns(for: "python", colors: colors)

        let swiftSample = """
        @MainActor
        /// Loads data
        func load() async throws -> Int { return 1 }
        """
        let pythonSample = """
        @dataclass
        async def load_data() -> int:
            return 1
        """

        XCTAssertTrue(matchesAnyPattern(in: swiftSample, from: swiftPatterns, expected: #"@\w+"#))
        XCTAssertTrue(matchesAnyPattern(in: swiftSample, from: swiftPatterns, expected: #"(?m)^(///).*$"#))
        XCTAssertTrue(matchesAnyPattern(in: swiftSample, from: swiftPatterns, expected: #"\b(func|struct|class|enum|protocol|extension|actor|if|else|for|while|switch|case|default|guard|defer|throw|try|catch|return|init|deinit|import|typealias|associatedtype|where|public|private|fileprivate|internal|open|static|mutating|nonmutating|inout|async|await|throws|rethrows)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: pythonSample, from: pythonPatterns, expected: #"@\w+"#))
        XCTAssertTrue(matchesAnyPattern(in: pythonSample, from: pythonPatterns, expected: #"\b(def|class|if|else|elif|for|while|try|except|with|as|import|from|return|yield|async|await)\b"#))
    }

    func testTypeScriptPatternsCoverLanguageSpecificConstructs() {
        let patterns = getSyntaxPatterns(for: "typescript", colors: colors)
        let emphasis = syntaxEmphasisPatterns(for: "typescript")
        let sample = """
        import type { Foo } from "./foo";

        @sealed
        export interface User<T extends Record<string, unknown>> {
            readonly id?: string;
            load(input: Partial<User<T>>): Promise<User<T>>;
        }

        type Result<T> = T extends Error ? never : T satisfies object;
        const fetchUser = async (id: string): Promise<User<number>> => {
            return client.users.get(id ?? "anonymous");
        };
        const themeProvider = (clientContext: any, parentTheme: Theme): Theme => {
            return defineTheme(parentTheme, darkTheme) as Theme;
        };
        """

        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b(function|class|interface|type|enum|const|let|var|if|else|for|while|do|try|catch|finally|return|extends|implements|import|export|from|as|async|await|new|throw|switch|case|default|break|continue|in|of|instanceof|typeof|void|delete|yield|public|private|protected|readonly|static|abstract|declare|namespace|module|keyof|infer|is|satisfies|asserts|constructor|override|get|set)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b(string|number|boolean|bigint|symbol|unknown|never|any|void|null|undefined|object|Record|Partial|Required|Readonly|Pick|Omit|Exclude|Extract|NonNullable|Parameters|ReturnType|InstanceType|Promise|Array|ReadonlyArray|Map|Set|WeakMap|WeakSet|Date|Error|RegExp)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b[A-Z][A-Za-z0-9_$]*\b"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"@[A-Za-z_$][A-Za-z0-9_$]*"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b[A-Za-z_$][A-Za-z0-9_$]*(?=\s*=\s*(?:async\s*)?\([^)]*\)\s*(?::\s*[^=\n]+?)?=>)"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b(?!if\b|for\b|while\b|switch\b|catch\b|function\b)[A-Za-z_$][A-Za-z0-9_$]*(?=\s*\()"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^\s*(?:readonly\s+)?[A-Za-z_$][A-Za-z0-9_$]*\??\s*:"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?<=\.)[A-Za-z_$][A-Za-z0-9_$]*\b"#))
        XCTAssertTrue(emphasis.keyword.contains(#"\b(function|class|interface|type|enum|const|let|var|if|else|for|while|do|try|catch|finally|return|extends|implements|import|export|from|as|async|await|new|throw|switch|case|default|break|continue|in|of|instanceof|typeof|void|delete|yield|public|private|protected|readonly|static|abstract|declare|namespace|module|keyof|infer|is|satisfies|asserts|constructor|override|get|set)\b"#))
    }

    func testAdaPatternsCoverPackagesCommentsAndAttributes() {
        let patterns = getSyntaxPatterns(for: "ada", colors: colors)
        let emphasis = syntaxEmphasisPatterns(for: "ada")
        let sample = """
        with Ada.Text_IO; use Ada.Text_IO;
        procedure Main is
        begin
           Put_Line ("Hello, World!"); -- greeting
        end Main;
        """

        XCTAssertTrue(
            patterns.keys.contains { pattern in
                pattern.contains("procedure")
                    && (try? NSRegularExpression(pattern: pattern))?.firstMatch(
                        in: sample,
                        options: [],
                        range: NSRange(sample.startIndex..<sample.endIndex, in: sample)
                    ) != nil
            }
        )
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)--.*$"#))
        XCTAssertTrue(emphasis.keyword.contains(#"(?i)\b(abort|abs|abstract|accept|access|aliased|all|and|array|at|begin|body|case|constant|declare|delay|delta|digits|do|else|elsif|end|entry|exception|exit|for|function|generic|goto|if|in|interface|is|limited|loop|mod|new|not|null|of|or|others|out|overriding|package|pragma|private|procedure|protected|raise|range|record|rem|renames|requeue|return|reverse|select|separate|subtype|synchronized|tagged|task|terminate|then|type|until|use|when|while|with|xor)\b"#))
    }

    func testYAMLPatternsSeparateKeysMarkersAndScalars() {
        let patterns = getSyntaxPatterns(for: "yml", colors: colors)
        let sample = """
        %YAML 1.2
        ---
        name: "Neon"
        services:
          - name: editor
            enabled: true
            retries: 3
            command: >-
              run --fast
        anchor: &default
        ref: *default
        !custom tagged
        # comment
        """

        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^\s*%[A-Z]+(?:\s+.*)?$"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^\s*(---|\.\.\.)\s*(?:#.*)?$"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^(\s*)-\s"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^\s*(?:-[ \t]+)?[A-Za-z0-9_.-]+\s*:"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\"([^\"\\]|\\.)*\"|'[^']*'"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b(true|false|null|yes|no|on|off)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b(-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\b"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"&[A-Za-z0-9_-]+|\*[A-Za-z0-9_-]+"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"!<[^>]+>|![A-Za-z0-9_./:-]+"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)#.*$"#))
    }

    func testScopeGuideVisualsExcludeSwiftOnly() {
        XCTAssertFalse(supportsScopeGuideVisuals(language: "swift"))
        XCTAssertFalse(supportsScopeGuideVisuals(language: " Swift "))
        XCTAssertTrue(supportsScopeGuideVisuals(language: "javascript"))
        XCTAssertTrue(supportsScopeGuideVisuals(language: "python"))
    }

    func testIndentationScopesAreLimitedToIndentationLanguages() {
        XCTAssertTrue(supportsIndentationScopes(language: "python"))
        XCTAssertTrue(supportsIndentationScopes(language: " YAML "))
        XCTAssertTrue(supportsIndentationScopes(language: "yml"))
        XCTAssertFalse(supportsIndentationScopes(language: "swift"))
        XCTAssertFalse(supportsIndentationScopes(language: "javascript"))
    }

    func testBracketScopeFindsNearestEnclosingScope() {
        let sample = """
        func demo() {
            if ready {
                print("ok")
            }
        }
        """
        let caret = (sample as NSString).range(of: #"print("ok")"#).location

        let match = computeBracketScopeMatch(text: sample, caretLocation: caret)

        XCTAssertNotNil(match)
        XCTAssertTrue(match?.guideMarkerRanges.isEmpty == false)
        XCTAssertTrue(isValidRange(match?.scopeRange ?? NSRange(location: NSNotFound, length: 0), utf16Length: (sample as NSString).length))
    }

    func testPythonIndentationScopeFromHeaderLine() {
        let sample = """
        def demo():
            if ready:
                print("ok")
            print("done")
        print("out")
        """
        let caret = (sample as NSString).range(of: "if ready:").location

        let match = computeIndentationScopeMatch(text: sample, caretLocation: caret)

        XCTAssertNotNil(match)
        XCTAssertTrue(match?.guideMarkerRanges.isEmpty == false)
        let scope = match?.scopeRange ?? NSRange(location: NSNotFound, length: 0)
        XCTAssertTrue(isValidRange(scope, utf16Length: (sample as NSString).length))
        XCTAssertFalse(NSLocationInRange((sample as NSString).range(of: #"print("out")"#).location, scope))
    }

    func testCodeMinimapSupportsCodeLanguagesOnly() {
        XCTAssertTrue(supportsCodeMinimap(language: "swift"))
        XCTAssertTrue(supportsCodeMinimap(language: " python "))
        XCTAssertFalse(supportsCodeMinimap(language: "plain"))
        XCTAssertFalse(supportsCodeMinimap(language: "markdown"))
        XCTAssertFalse(supportsCodeMinimap(language: "csv"))
    }

    func testAppleCrashReportPatternsMatchCrashFieldsAndBacktraces() {
        let patterns = getSyntaxPatterns(for: "crashlog", colors: colors)
        let sample = """
        Exception Type: EXC_BAD_ACCESS (SIGSEGV)
        Crashed Thread: 0
        Thread 0 Crashed:
        0   ExampleApp  0x0000000100000000 main + 12
        Binary Images:
        """

        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^(Exception Type|Exception Codes|Exception Subtype|Termination Reason|Termination Signal|Crashed Thread):"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"(?m)^Thread\s+\d+(?:\s+Crashed)?\s*:.*$"#))
        XCTAssertTrue(matchesAnyPattern(in: sample, from: patterns, expected: #"\b0x[0-9A-Fa-f]+\b"#))
    }

#if os(macOS)
    func testContentInstallRefreshPolicyLimitsFullLayoutToSmallDocuments() {
        XCTAssertTrue(MacEditorContentInstallRefreshPolicy.shouldInvalidateFullRange(textLength: 120_000))
        XCTAssertFalse(MacEditorContentInstallRefreshPolicy.shouldInvalidateFullRange(textLength: 120_001))
        XCTAssertFalse(MacEditorContentInstallRefreshPolicy.shouldInvalidateFullRange(textLength: EditorRuntimeLimits.syntaxMinimalUTF16Length))
    }

    func testBoldKeywordSelectionOverlaysUseStableContiguousLayoutPolicy() {
        XCTAssertFalse(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: false,
                boldKeywords: true,
                highlightCurrentLine: true,
                highlightMatchingBrackets: false,
                isLargeFileMode: false
            ),
            "Bold keywords plus current-line overlay should avoid AppKit non-contiguous layout flicker while line wrap is off."
        )
        XCTAssertFalse(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: false,
                boldKeywords: true,
                highlightCurrentLine: false,
                highlightMatchingBrackets: true,
                isLargeFileMode: false
            ),
            "Bold keywords plus bracket overlay should avoid AppKit non-contiguous layout flicker while line wrap is off."
        )
        XCTAssertFalse(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: false,
                boldKeywords: false,
                highlightCurrentLine: true,
                highlightMatchingBrackets: true,
                isLargeFileMode: false
            ),
            "Normal files use contiguous TextKit layout so loaded content and mouse hit testing share one stable glyph map."
        )
        XCTAssertFalse(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: true,
                boldKeywords: false,
                highlightCurrentLine: false,
                highlightMatchingBrackets: false,
                isLargeFileMode: false
            )
        )
        XCTAssertTrue(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: false,
                boldKeywords: false,
                highlightCurrentLine: false,
                highlightMatchingBrackets: false,
                isLargeFileMode: true
            )
        )
        XCTAssertTrue(
            CustomTextEditor.shouldAllowNonContiguousLayout(
                wrapMode: false,
                boldKeywords: true,
                highlightCurrentLine: true,
                highlightMatchingBrackets: true,
                isLargeFileMode: true
            ),
            "Large-file mode suppresses selection overlays so TextKit can retain non-contiguous layout."
        )
    }
#endif

    func testCodeMinimapMarksCommentsAndSections() {
        let sample = """
        // MARK: - Setup
        import SwiftUI
        struct Demo {
            // regular comment
            // TODO: tighten validation
            let value: Int
            if value > 0 {
                return
            }
        }
        """

        let snapshot = buildCodeMinimapSnapshot(text: sample, language: "swift")

        XCTAssertTrue(snapshot.markers.contains { $0.kind == .section })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .comment })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .declaration })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .importLine })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .property })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .controlFlow })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .code })
    }

    func testCodeMinimapUsesLanguageSpecificCommentMarkers() {
        let sample = """
        # SECTION: Parser
        def demo():
            # comment
            value = 1
            return 1
        """

        let snapshot = buildCodeMinimapSnapshot(text: sample, language: "python")

        XCTAssertTrue(snapshot.markers.contains { $0.kind == .section })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .comment })
        XCTAssertTrue(snapshot.markers.contains { $0.kind == .code })
    }

    func testCodeMinimapViewportTracksVisibleOffset() {
        let viewport = codeMinimapViewport(
            visibleY: 450,
            visibleHeight: 300,
            contentHeight: 1_200
        )

        XCTAssertEqual(viewport.topFraction, 0.5, accuracy: 0.0001)
        XCTAssertEqual(viewport.heightFraction, 0.25, accuracy: 0.0001)
    }

    func testCodeMinimapScrollOffsetUsesViewportFraction() {
        let offset = codeMinimapScrollOffset(
            topFraction: 0.5,
            contentHeight: 2_000,
            visibleHeight: 500
        )

        XCTAssertEqual(offset, 750, accuracy: 0.0001)
    }

    func testCodeMinimapViewportMarkerUsesVisibleViewportFractions() {
        let marker = codeMinimapViewportMarker(
            viewport: CodeMinimapViewport(topFraction: 0.5, heightFraction: 0.25)
        )

        XCTAssertEqual(marker?.yFraction ?? -1, 0.375, accuracy: 0.0001)
        XCTAssertEqual(marker?.heightFraction ?? -1, 0.25, accuracy: 0.0001)
    }

    func testCodeMinimapViewportMarkerIsHiddenForFullViewport() {
        let marker = codeMinimapViewportMarker(
            viewport: CodeMinimapViewport(topFraction: 0, heightFraction: 1)
        )

        XCTAssertNil(marker)
    }

    func testCodeMinimapViewportTopFractionFollowsDraggedMarkerCenter() {
        XCTAssertEqual(
            codeMinimapViewportTopFraction(markerCenterYFraction: 0.5, viewportHeightFraction: 0.25),
            0.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            codeMinimapViewportTopFraction(markerCenterYFraction: 0.02, viewportHeightFraction: 0.25),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            codeMinimapViewportTopFraction(markerCenterYFraction: 0.98, viewportHeightFraction: 0.25),
            1,
            accuracy: 0.0001
        )
    }

    private func matchesAnyPattern(in text: String, from map: [String: Color], expected pattern: String) -> Bool {
        guard let color = map[pattern],
              let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        _ = color
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func matchesRegex(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func anySyntaxPatternMatches(_ text: String, from map: [String: Color]) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in map.keys {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            if regex.firstMatch(in: text, options: [], range: range) != nil {
                return true
            }
        }
        return false
    }
}

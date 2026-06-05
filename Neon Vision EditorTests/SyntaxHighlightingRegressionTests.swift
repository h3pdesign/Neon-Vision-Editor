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
        XCTAssertTrue(matchesRegex(htmlSample, pattern: #"<[^>]+>"#))
        XCTAssertTrue(matchesRegex(htmlSample, pattern: #"\"[^\"]*\"|'[^']*'"#))
        XCTAssertTrue(matchesRegex(cssSample, pattern: #"\b([a-zA-Z-]+)\s*:"#))
        XCTAssertTrue(matchesRegex(cssSample, pattern: #"#[0-9A-Fa-f]{3,6}\b"#))
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

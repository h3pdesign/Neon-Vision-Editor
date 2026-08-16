import Foundation
import UniformTypeIdentifiers

@main
struct QuickLookSyntaxRegressionRunner {
    private struct Case {
        let name: String
        let fileExtension: String
        let fileName: String
        let source: String
        let requiredKinds: Set<TokenKind>
    }

    private static let cases: [Case] = [
        Case(
            name: "Swift declarations",
            fileExtension: "swift",
            fileName: "Model.swift",
            source: "import Foundation\nstruct Item { let value = 42 // note\n}",
            requiredKinds: [.keyword, .type, .number, .comment]
        ),
        Case(
            name: "TypeScript declarations",
            fileExtension: "ts",
            fileName: "model.ts",
            source: "interface Item { readonly value: number }\nconst item = { value: 42 };",
            requiredKinds: [.keyword, .type, .number]
        ),
        Case(
            name: "Python declarations",
            fileExtension: "py",
            fileName: "model.py",
            source: "from pathlib import Path\nclass Item:\n    value = 42 # note",
            requiredKinds: [.keyword, .type, .number, .comment]
        ),
        Case(
            name: "lowercase SQL",
            fileExtension: "sql",
            fileName: "query.sql",
            source: "select name, count(*) from users where active = true;",
            requiredKinds: [.keyword, .type]
        ),
        Case(
            name: "TeX commands and comments",
            fileExtension: "tex",
            fileName: "paper.tex",
            source: "\\section{Overview}\nValue is \\textbf{important}. % note",
            requiredKinds: [.keyword, .comment]
        ),
        Case(
            name: "TOML structure",
            fileExtension: "toml",
            fileName: "settings.toml",
            source: "[server]\nhost = \"localhost\"\nport = 8080\nenabled = true",
            requiredKinds: [.type, .keyword, .string, .number]
        ),
        Case(
            name: "strings keys and comments",
            fileExtension: "strings",
            fileName: "Localizable.strings",
            source: "\"welcome.title\" = \"Welcome\"; // greeting",
            requiredKinds: [.keyword, .string, .comment]
        ),
        Case(
            name: "notebook JSON keys",
            fileExtension: "ipynb",
            fileName: "Example.ipynb",
            source: "{\"cells\": [{\"cell_type\": \"code\", \"execution_count\": 2}]}",
            requiredKinds: [.keyword, .string, .number]
        ),
        Case(
            name: "extensionless Dockerfile",
            fileExtension: "",
            fileName: "Dockerfile",
            source: "FROM swift:latest\nWORKDIR /src\nCOPY . .\nRUN swift build",
            requiredKinds: [.keyword]
        ),
        Case(
            name: "YAML keys and values",
            fileExtension: "yaml",
            fileName: "service.yaml",
            source: "service:\n  enabled: true\n  port: 8080\n  image: \"neon:latest\" # note",
            requiredKinds: [.keyword, .string, .number, .comment]
        ),
        Case(
            name: "HTML tags and attributes",
            fileExtension: "html",
            fileName: "index.html",
            source: "<section class=\"hero\"><h1>Hello</h1></section>",
            requiredKinds: [.type, .keyword, .string]
        ),
        Case(
            name: "CSS declarations",
            fileExtension: "css",
            fileName: "theme.css",
            source: "/* theme */ .hero { color: #ff00aa; padding: 12px; }",
            requiredKinds: [.comment, .keyword, .number]
        )
    ]

    static func main() {
        let highlighter = SyntaxHighlighter()
        for testCase in cases {
            let tokens = highlighter.highlight(
                testCase.source,
                contentType: .plainText,
                fileExtension: testCase.fileExtension,
                fileName: testCase.fileName
            )
            let kinds = Set(tokens.map(\.kind))
            let missing = testCase.requiredKinds.subtracting(kinds)
            guard missing.isEmpty else {
                fputs("Quick Look syntax regression for \(testCase.name); missing token kinds: \(missing)\n", stderr)
                exit(1)
            }
            for token in tokens {
                guard token.range.lowerBound >= testCase.source.startIndex,
                      token.range.upperBound <= testCase.source.endIndex,
                      token.range.lowerBound <= token.range.upperBound else {
                    fputs("Quick Look syntax regression for \(testCase.name); invalid token range\n", stderr)
                    exit(1)
                }
            }
        }

        let unicodeHTML = "<p>Hej 👋</p><style>.titel { color: red; }</style>"
        let unicodeTokens = highlighter.highlight(
            unicodeHTML,
            contentType: .html,
            fileExtension: "html",
            fileName: "unicode.html"
        )
        guard unicodeTokens.contains(where: { token in
            token.kind == .keyword && unicodeHTML[token.range] == "color"
        }) else {
            fputs("Quick Look syntax regression for Unicode embedded CSS range translation\n", stderr)
            exit(1)
        }

        let longPlainTeX = String(repeating: "ordinary prose ", count: 1_000)
        let longTeXTokens = highlighter.highlight(
            longPlainTeX,
            contentType: .plainText,
            fileExtension: "tex",
            fileName: "long.tex"
        )
        guard longTeXTokens.count <= 4 else {
            fputs("Quick Look TeX tokenizer emitted excessive plain-span tokens: \(longTeXTokens.count)\n", stderr)
            exit(1)
        }

        let longCSVField = String(repeating: "a", count: 16_000)
        let longCSVTokens = highlighter.highlight(
            "header\n\(longCSVField)",
            contentType: .plainText,
            fileExtension: "csv",
            fileName: "long.csv"
        )
        guard longCSVTokens.count <= 4 else {
            fputs("Quick Look CSV tokenizer emitted excessive plain-span tokens: \(longCSVTokens.count)\n", stderr)
            exit(1)
        }
        print("Quick Look syntax regressions passed (\(cases.count) language routes).")
    }
}

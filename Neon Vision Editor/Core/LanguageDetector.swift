import Foundation

public struct LanguageDetector {
    public static let shared = LanguageDetector()
    private init() {}

    // Detection toggles (enabled by default)
    public static var csharpDetectionEnabled: Bool = true
    public static var cDetectionEnabled: Bool = true

    // Known extension to language map
    private let extensionMap: [String: String] = [
        "swift": "swift",
        "py": "python",
        "pyi": "python",
        "js": "javascript",
        "mjs": "javascript",
        "cjs": "javascript",
        "ts": "typescript",
        "tsx": "typescript",
        "php": "php",
        "phtml": "php",
        "csv": "csv",
        "tsv": "csv",
        "toml": "toml",
        "ini": "ini",
        "yaml": "yaml",
        "yml": "yaml",
        "xml": "xml",
        "plist": "xml",
        "sql": "sql",
        "log": "log",
        "vim": "vim",
        "ipynb": "ipynb",
        "java": "java",
        "kt": "kotlin",
        "kts": "kotlin",
        "go": "go",
        "rb": "ruby",
        "rs": "rust",
        "ps1": "powershell",
        "psm1": "powershell",
        "html": "html",
        "htm": "html",
        "ee": "expressionengine",
        "exp": "expressionengine",
        "tmpl": "expressionengine",
        "css": "css",
        "c": "c",
        "cpp": "cpp",
        "cc": "cpp",
        "hpp": "cpp",
        "hh": "cpp",
        "h": "cpp",
        "m": "objective-c",
        "mm": "objective-c",
        "cs": "csharp",
        "json": "json",
        "jsonc": "json",
        "json5": "json",
        "md": "markdown",
        "markdown": "markdown",
        "env": "dotenv",
        "proto": "proto",
        "graphql": "graphql",
        "gql": "graphql",
        "rst": "rst",
        "conf": "nginx",
        "nginx": "nginx",
        "cob": "cobol",
        "cbl": "cobol",
        "cobol": "cobol",
        "sh": "bash",
        "bash": "bash",
        "zsh": "zsh"
    ]

    private let dotfileMap: [String: String] = [
        ".zshrc": "zsh",
        ".zprofile": "zsh",
        ".zlogin": "zsh",
        ".zlogout": "zsh",
        ".bashrc": "bash",
        ".bash_profile": "bash",
        ".bash_login": "bash",
        ".bash_logout": "bash",
        ".profile": "bash",
        ".vimrc": "vim",
        ".env": "dotenv",
        ".envrc": "dotenv",
        ".gitconfig": "ini"
    ]

    public struct Result {
        public let lang: String
        public let scores: [String: Int]
        public let confidence: Int // difference between top-1 and top-2
    }

    public func preferredLanguage(for fileURL: URL?) -> String? {
        guard let fileURL else { return nil }
        let fileName = fileURL.lastPathComponent.lowercased()
        if fileName.hasPrefix(".env") { return "dotenv" }
        if let mapped = dotfileMap[fileName] { return mapped }
        let ext = fileURL.pathExtension.lowercased()
        return extensionMap[ext]
    }

    public func detect(text: String, name: String?, fileURL: URL?) -> Result {
        let sample = String(text.prefix(120_000))
        let lower = sample.lowercased()
        let trimForDetection = UserDefaults.standard.bool(forKey: "SettingsTrimWhitespaceForSyntaxDetection")
        let detectionInput = trimForDetection ? lower.trimmingCharacters(in: .whitespacesAndNewlines) : lower

        var scores: [String: Int] = [:]
        let languages = [
            "swift", "csharp", "php", "csv", "python", "javascript", "typescript", "java", "kotlin",
            "go", "ruby", "rust", "dotenv", "proto", "graphql", "rst", "nginx", "cpp", "c",
            "css", "markdown", "json", "html", "expressionengine", "sql", "xml", "yaml", "toml", "ini", "vim",
            "log", "ipynb", "powershell", "cobol", "objective-c", "bash", "zsh"
        ]
        for lang in languages { scores[lang] = 0 }

        func bump(_ lang: String, _ amount: Int) {
            scores[lang, default: 0] += amount
        }

        // Extension/dotfile hint
        if let byURL = preferredLanguage(for: fileURL) {
            bump(byURL, 300)
        } else if let name {
            let lowerName = name.lowercased()
            if let mapped = dotfileMap[lowerName] {
                bump(mapped, 300)
            } else {
                let ext = URL(fileURLWithPath: lowerName).pathExtension.lowercased()
                if let mapped = extensionMap[ext] { bump(mapped, 300) }
            }
        }

        // Shebangs
        if detectionInput.hasPrefix("#!") {
            if detectionInput.contains("python") { bump("python", 400) }
            if detectionInput.contains("bash") { bump("bash", 350) }
            if detectionInput.contains("zsh") { bump("zsh", 350) }
            if detectionInput.contains("/bin/sh") { bump("bash", 200) }
            if detectionInput.contains("node") { bump("javascript", 300) }
            if detectionInput.contains("ruby") { bump("ruby", 300) }
            if detectionInput.contains("php") { bump("php", 300) }
            if detectionInput.contains("pwsh") || detectionInput.contains("powershell") { bump("powershell", 300) }
        }

        // JSON / ipynb
        if looksLikeJSON(detectionInput, trimEdges: false) { bump("json", 140) }
        if lower.contains("\"cells\"") && lower.contains("\"cell_type\"") {
            bump("ipynb", 220)
            bump("json", 40)
        }

        // XML / HTML
        if lower.contains("<?xml") { bump("xml", 200) }
        if regexBool(lower, pattern: "<!doctype\\s+html") || lower.contains("<html") || lower.contains("<body") {
            bump("html", 160)
        }
        if regexBool(lower, pattern: "(?m)^\\s*<[^>]+>") { bump("html", 40) }
        if regexBool(lower, pattern: "\\{/?exp:[a-z0-9_:-]+[^}]*\\}") {
            bump("expressionengine", 220)
            bump("html", 40)
        }
        if regexBool(lower, pattern: "\\{if(?::elseif)?\\b[^}]*\\}|\\{\\/if\\}|\\{:else\\}") { bump("expressionengine", 140) }
        if regexBool(lower, pattern: "\\{!--[\\s\\S]*?--\\}") { bump("expressionengine", 120) }

        // CSS
        let cssPropertyCount = regexCount(lower, pattern: "(?m)^\\s*[a-z-]+\\s*:\\s*[^;]+;\\s*$")
        if cssPropertyCount >= 2 { bump("css", min(160, cssPropertyCount * 18)) }
        if regexBool(lower, pattern: "(?m)[^\\S\\n]*[#\\.][A-Za-z0-9_-]+\\s*\\{") { bump("css", 60) }
        if lower.contains("@media") || lower.contains("@keyframes") { bump("css", 80) }

        // YAML / TOML / INI / dotenv / CSV
        if regexBool(lower, pattern: "(?m)^\\s*---\\s*$|(?m)^\\s*\\.\\.\\.\\s*$") { bump("yaml", 120) }
        let yamlKeyCount = regexCount(lower, pattern: "(?m)^\\s*[A-Za-z0-9_.-]+\\s*:\\s+.+$")
        let yamlListCount = regexCount(lower, pattern: "(?m)^\\s*-\\s+.+$")
        if yamlKeyCount > 0 { bump("yaml", min(200, yamlKeyCount * 14)) }
        if yamlListCount > 0 { bump("yaml", min(120, yamlListCount * 8)) }

        let tomlSectionCount = regexCount(lower, pattern: "(?m)^\\s*\\[[^\\]\\n]+\\]\\s*$")
        let tomlAssignCount = regexCount(lower, pattern: "(?m)^\\s*[A-Za-z0-9_.-]+\\s*=\\s*.+$")
        if tomlSectionCount > 0 && tomlAssignCount > 0 {
            bump("toml", min(180, (tomlSectionCount + tomlAssignCount) * 10))
        }

        let iniAssignCount = regexCount(lower, pattern: "(?m)^\\s*[A-Za-z0-9_.-]+\\s*=\\s*.+$")
        if tomlSectionCount > 0 && iniAssignCount > 0 {
            bump("ini", min(160, (tomlSectionCount + iniAssignCount) * 8))
        }

        let dotenvCount = regexCount(lower, pattern: "(?m)^[A-Z_][A-Z0-9_]*=.+$")
        if dotenvCount > 0 && tomlSectionCount == 0 { bump("dotenv", min(160, dotenvCount * 10)) }

        if looksLikeCSV(text) { bump("csv", 140) }

        // Markdown
        let mdHeadingCount = regexCount(lower, pattern: "(?m)^\\s{0,3}#{1,6}\\s+.+$")
        if mdHeadingCount > 0 { bump("markdown", min(200, mdHeadingCount * 20)) }
        let mdListCount = regexCount(lower, pattern: "(?m)^\\s*([-*+]\\s+|\\d+\\.\\s+).+$")
        if mdListCount > 1 { bump("markdown", min(120, mdListCount * 8)) }
        if lower.contains("```") { bump("markdown", 90) }
        if regexBool(lower, pattern: "(?m)^\\s*>\\s+.+$") { bump("markdown", 40) }
        if regexBool(lower, pattern: "\\[[^\\]]+\\]\\([^\\)]+\\)") { bump("markdown", 40) }

        // SQL
        if regexBool(lower, pattern: "\\b(select|insert|update|delete|from|where|join|group by|order by|create table|alter table)\\b") {
            bump("sql", 120)
        }

        // Swift
        if lower.contains("import swiftui") { bump("swift", 200) }
        if lower.contains("import foundation") { bump("swift", 80) }
        if regexBool(lower, pattern: "\\bstruct\\s+\\w+\\s*:\\s*view\\b") { bump("swift", 120) }
        if lower.contains("@main") { bump("swift", 80) }
        if lower.contains("func ") { bump("swift", 40) }
        if regexBool(lower, pattern: "\\b(let|var)\\s+\\w+\\s*:\\s*") { bump("swift", 40) }

        // Objective-C
        if lower.contains("@interface") || lower.contains("@implementation") { bump("objective-c", 160) }
        if lower.contains("#import") { bump("objective-c", 80); bump("c", 40); bump("cpp", 40) }
        if lower.contains("nslog") { bump("objective-c", 60) }
        if regexBool(lower, pattern: "@autoreleasepool|@property") { bump("objective-c", 60) }

        // C / C++
        if LanguageDetector.cDetectionEnabled {
            if lower.contains("#include") { bump("c", 80); bump("cpp", 80) }
            if regexBool(lower, pattern: "\\bint\\s+main\\s*\\(") { bump("c", 60); bump("cpp", 60) }
            if lower.contains("printf(") { bump("c", 40) }
            if lower.contains("std::") || lower.contains("cout <<") || lower.contains("template<") { bump("cpp", 120) }
        }

        // C#
        if LanguageDetector.csharpDetectionEnabled {
            if lower.contains("using system") { bump("csharp", 160) }
            if lower.contains("namespace ") { bump("csharp", 80) }
            if regexBool(lower, pattern: "\\bpublic\\s+static\\s+void\\s+main\\s*\\(") { bump("csharp", 80) }
            if lower.contains("console.writeline") { bump("csharp", 80) }
            if regexBool(lower, pattern: "(?m)^\\s*\\[[A-Za-z]+\\]") { bump("csharp", 40) }
        }

        // Java
        if lower.contains("public class ") { bump("java", 120) }
        if lower.contains("package ") { bump("java", 40); bump("kotlin", 30); bump("go", 30) }
        if lower.contains("system.out.println") { bump("java", 80) }
        if regexBool(lower, pattern: "\\bimport\\s+java\\.") { bump("java", 60) }

        // Kotlin
        if lower.contains("fun ") { bump("kotlin", 80) }
        if lower.contains("data class ") { bump("kotlin", 100) }
        if regexBool(lower, pattern: "\\bval\\s+\\w+\\s*[:=]") { bump("kotlin", 60) }
        if regexBool(lower, pattern: "\\bvar\\s+\\w+\\s*[:=]") { bump("kotlin", 60) }

        // Go
        if regexBool(lower, pattern: "\\bpackage\\s+\\w+") { bump("go", 80) }
        if regexBool(lower, pattern: "\\bfunc\\s+\\w+\\s*\\(") { bump("go", 60) }
        if lower.contains(":=") { bump("go", 40) }
        if lower.contains("fmt.") { bump("go", 40) }

        // Rust
        if regexBool(lower, pattern: "\\bfn\\s+\\w+\\s*\\(") { bump("rust", 60) }
        if lower.contains("let mut") { bump("rust", 60) }
        if lower.contains("crate::") || lower.contains("use ") { bump("rust", 40) }

        // Python
        if regexBool(lower, pattern: "(?m)^\\s*def\\s+\\w+\\s*\\(") { bump("python", 80) }
        if regexBool(lower, pattern: "(?m)^\\s*class\\s+\\w+") { bump("python", 60) }
        if lower.contains("import ") { bump("python", 30) }
        if lower.contains("if __name__ == \"__main__\"") { bump("python", 120) }
        if lower.contains("elif ") { bump("python", 20) }
        if lower.contains("self") { bump("python", 20) }

        // JavaScript / TypeScript
        if regexBool(lower, pattern: "\\bfunction\\s+\\w+\\s*\\(") { bump("javascript", 50); bump("typescript", 20) }
        if lower.contains("=>") { bump("javascript", 40); bump("typescript", 20) }
        if regexBool(lower, pattern: "\\b(const|let|var)\\s+\\w+") { bump("javascript", 40); bump("typescript", 20) }
        if lower.contains("console.log") { bump("javascript", 40) }
        if regexBool(lower, pattern: "\\bimport\\s+.+from\\s+['\"]") { bump("javascript", 40); bump("typescript", 40) }
        if regexBool(lower, pattern: "\\bexport\\s+(default\\s+)?") { bump("javascript", 30); bump("typescript", 30) }
        if regexBool(lower, pattern: "\\binterface\\s+\\w+") { bump("typescript", 100) }
        if regexBool(lower, pattern: "\\btype\\s+\\w+\\s*=") { bump("typescript", 80) }
        if regexBool(lower, pattern: "\\bimplements\\b|\\breadonly\\b") { bump("typescript", 60) }
        if regexBool(lower, pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\s*:\\s*(string|number|boolean|any|unknown|never)\\b") {
            bump("typescript", 80)
        }

        // PHP
        if lower.contains("<?php") || lower.contains("<?=") { bump("php", 180) }
        if regexBool(lower, pattern: "\\$[A-Za-z_][A-Za-z0-9_]*") { bump("php", 40) }
        if regexBool(lower, pattern: "\\bnamespace\\s+\\w+") { bump("php", 40) }

        // Bash / Zsh
        if regexBool(lower, pattern: "(?m)^\\s*#!.*\\b(bash|zsh|sh)\\b") { bump("bash", 60) }
        if regexBool(lower, pattern: "(?m)^\\s*(export\\s+)?[A-Za-z_][A-Za-z0-9_]*=") { bump("bash", 20); bump("zsh", 20) }
        if lower.contains("set -e") || lower.contains("set -u") { bump("bash", 40); bump("zsh", 40) }
        if lower.contains("autoload") || lower.contains("typeset -") { bump("zsh", 60) }

        // GraphQL / Proto / Nginx / RST / Vim / PowerShell / COBOL / Log
        if regexBool(lower, pattern: "\\b(schema|type|query|mutation|fragment)\\b") && lower.contains("{") { bump("graphql", 100) }
        if lower.contains("syntax = \"proto") || lower.contains("message ") { bump("proto", 120) }
        if lower.contains("service ") && lower.contains("rpc ") { bump("proto", 80) }
        if lower.contains("server {") || lower.contains("location /") || lower.contains("http {") { bump("nginx", 120) }
        if lower.contains(".. toctree::") || lower.contains(".. code-block::") { bump("rst", 120) }
        if lower.contains("nnoremap") || lower.contains("inoremap") || regexBool(lower, pattern: "(?m)^\\s*set\\s+") { bump("vim", 80) }
        if lower.contains("write-host") || lower.contains("param(") || lower.contains("$psversiontable") { bump("powershell", 120) }
        if lower.contains("identification division") || lower.contains("program-id") { bump("cobol", 180) }
        if regexBool(lower, pattern: "(?m)^(error|warn|warning|info|debug|trace)\\b") { bump("log", 80) }

        // Prefer higher of JS/TS when both present
        if scores["typescript", default: 0] > scores["javascript", default: 0] {
            bump("javascript", -15)
        }

        // Prefer YAML when both YAML and Markdown are present
        if scores["yaml", default: 0] > scores["markdown", default: 0] {
            bump("markdown", -10)
        }

        // Pick top 2
        let sorted = scores.sorted { $0.value > $1.value }
        let top = sorted.first ?? ("plain", 0)
        let second = sorted.dropFirst().first ?? ("plain", 0)
        let confidence = max(0, top.value - second.value)
        let minScore = 10
        let lang = top.value >= minScore ? top.key : "plain"
        return Result(lang: lang, scores: scores, confidence: confidence)
    }

    private func regexBool(_ text: String, pattern: String) -> Bool {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.firstMatch(in: text, options: [], range: range) != nil
        } catch {
            return false
        }
    }

    private func regexCount(_ text: String, pattern: String) -> Int {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.numberOfMatches(in: text, options: [], range: range)
        } catch {
            return 0
        }
    }

    private func looksLikeJSON(_ text: String, trimEdges: Bool = false) -> Bool {
        let candidate = trimEdges ? text.trimmingCharacters(in: .whitespacesAndNewlines) : text
        guard candidate.hasPrefix("{") || candidate.hasPrefix("[") else { return false }
        if regexBool(candidate, pattern: "\"[^\"]+\"\\s*:\\s*") { return true }
        if candidate.hasPrefix("[") && candidate.contains("]") { return true }
        return false
    }

    private func looksLikeCSV(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count < 2 { return false }
        let sample = lines.prefix(6)
        let counts = sample.map { line in line.filter { $0 == "," }.count }
        guard let first = counts.first, first > 0 else { return false }
        let consistent = counts.dropFirst().allSatisfy { abs($0 - first) <= 1 }
        return consistent
    }
}

import SwiftUI
import Foundation
#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

enum CodeTemplateCatalog {
    static let supportedLanguages: [String] = [
        "swift", "ada", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "fish", "perl", "lua", "r",
        "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "dockerfile", "makefile", "hcl", "xcconfig", "strings",
        "csharp", "objective-c", "json", "xml", "yaml", "toml", "nix", "eml", "csv", "ini", "vim", "log", "crashlog", "ipynb",
        "markdown", "typst", "tex", "bash", "zsh", "powershell", "standard", "plain"
    ]

    static func overrideKey(for language: String) -> String {
        "TemplateOverride_\(language)"
    }

    static func defaultTemplate(for language: String) -> String? {
        switch language {
        case "swift":
            return template([
                "import Foundation",
                "",
                "func main() {",
                "    let name = CommandLine.arguments.dropFirst().first ?? \"World\"",
                "    print(\"Hello, \\(name)!\")",
                "}",
                "",
                "main()"
            ])
        case "python":
            return template([
                "from __future__ import annotations",
                "",
                "",
                "def main() -> None:",
                "    print(\"Hello, World!\")",
                "",
                "",
                "if __name__ == \"__main__\":",
                "    main()"
            ])
        case "javascript":
            return template([
                "\"use strict\";",
                "",
                "function main() {",
                "  const message = \"Hello, World!\";",
                "  console.log(message);",
                "}",
                "",
                "main();"
            ])
        case "typescript":
            return template([
                "function greet(name: string): string {",
                "  return `Hello, ${name}!`;",
                "}",
                "",
                "console.log(greet(\"World\"));"
            ])
        case "php":
            return template([
                "<?php",
                "",
                "declare(strict_types=1);",
                "",
                "function greet(string $name): string",
                "{",
                "    return \"Hello, {$name}!\";",
                "}",
                "",
                "echo greet('World') . PHP_EOL;"
            ])
        case "java":
            return template([
                "public final class Main {",
                "    public static void main(String[] args) {",
                "        String name = args.length > 0 ? args[0] : \"World\";",
                "        System.out.printf(\"Hello, %s!%n\", name);",
                "    }",
                "}"
            ])
        case "kotlin":
            return template([
                "fun main(args: Array<String>) {",
                "    val name = args.firstOrNull() ?: \"World\"",
                "    println(\"Hello, $name!\")",
                "}"
            ])
        case "go":
            return template([
                "package main",
                "",
                "import \"fmt\"",
                "",
                "func main() {",
                "\tfmt.Println(\"Hello, World!\")",
                "}"
            ])
        case "ruby":
            return template([
                "def greet(name)",
                "  \"Hello, #{name}!\"",
                "end",
                "",
                "puts greet(ARGV.first || \"World\")"
            ])
        case "rust":
            return template([
                "fn main() {",
                "    let name = std::env::args().nth(1).unwrap_or_else(|| \"World\".into());",
                "    println!(\"Hello, {name}!\");",
                "}"
            ])
        case "fish":
            return template(["function greet", "    echo Hello, World!", "end", "", "greet"])
        case "perl":
            return template(["use strict;", "use warnings;", "", "sub greet { return \"Hello, World!\\n\"; }", "", "print greet();"])
        case "lua":
            return template(["local function greet(name)", "  return \"Hello, \" .. name .. \"!\"", "end", "", "print(greet(\"World\"))"])
        case "r":
            return template(["greet <- function(name) {", "  paste(\"Hello,\", name, \"!\")", "}", "", "print(greet(\"World\"))"])
        case "dockerfile":
            return template(["FROM swift:6.0", "", "WORKDIR /app", "COPY . .", "RUN swift build -c release", "", "CMD [\".build/release/App\"]"])
        case "makefile":
            return template([".PHONY: build test", "", "build:", "\tswift build", "", "test:", "\tswift test"])
        case "hcl":
            return template(["terraform {", "  required_version = \">= 1.0\"", "}", "", "variable \"name\" {", "  type    = string", "  default = \"example\"", "}"])
        case "xcconfig":
            return template(["PRODUCT_BUNDLE_IDENTIFIER = com.example.app", "MARKETING_VERSION = 1.0", "CURRENT_PROJECT_VERSION = 1"])
        case "strings":
            return template(["/* Localized strings */", "\"welcome.title\" = \"Welcome\";"])
        case "ada":
            return template([
                "with Ada.Text_IO; use Ada.Text_IO;",
                "",
                "procedure Main is",
                "begin",
                "   Put_Line (\"Hello, World!\");",
                "end Main;"
            ])
        case "cobol":
            return template([
                "       IDENTIFICATION DIVISION.",
                "       PROGRAM-ID. HELLO-WORLD.",
                "",
                "       PROCEDURE DIVISION.",
                "           DISPLAY \"Hello, World!\"",
                "           STOP RUN."
            ])
        case "dotenv":
            return template([
                "APP_ENV=development",
                "APP_PORT=3000",
                "LOG_LEVEL=info",
                "# API_TOKEN=replace-me"
            ])
        case "proto":
            return template([
                "syntax = \"proto3\";",
                "",
                "package example.v1;",
                "",
                "message GreetingRequest {",
                "  string name = 1;",
                "}",
                "",
                "message GreetingResponse {",
                "  string message = 1;",
                "}",
                "",
                "service Greeter {",
                "  rpc Greet(GreetingRequest) returns (GreetingResponse);",
                "}"
            ])
        case "graphql":
            return template([
                "type Query {",
                "  greeting(name: String = \"World\"): String!",
                "}",
                "",
                "query Greeting {",
                "  greeting(name: \"Neon\")",
                "}"
            ])
        case "rst":
            return template([
                "Project Title",
                "=============",
                "",
                "A short project summary.",
                "",
                "Getting Started",
                "---------------",
                "",
                "#. Install the dependencies.",
                "#. Run the project."
            ])
        case "nginx":
            return template([
                "server {",
                "    listen 80;",
                "    server_name example.com;",
                "",
                "    root /var/www/html;",
                "    index index.html;",
                "",
                "    location / {",
                "        try_files $uri $uri/ =404;",
                "    }",
                "}"
            ])
        case "c":
            return template([
                "#include <stdio.h>",
                "",
                "int main(int argc, char *argv[]) {",
                "    const char *name = argc > 1 ? argv[1] : \"World\";",
                "    printf(\"Hello, %s!\\n\", name);",
                "    return 0;",
                "}"
            ])
        case "cpp":
            return template([
                "#include <iostream>",
                "#include <string>",
                "",
                "int main(int argc, char *argv[]) {",
                "    const std::string name = argc > 1 ? argv[1] : \"World\";",
                "    std::cout << \"Hello, \" << name << \"!\\n\";",
                "    return 0;",
                "}"
            ])
        case "csharp":
            return template([
                "string name = args.Length > 0 ? args[0] : \"World\";",
                "Console.WriteLine($\"Hello, {name}!\");"
            ])
        case "objective-c":
            return template([
                "#import <Foundation/Foundation.h>",
                "",
                "int main(int argc, const char *argv[]) {",
                "    @autoreleasepool {",
                "        NSString *name = argc > 1 ? @(argv[1]) : @\"World\";",
                "        NSLog(@\"Hello, %@!\", name);",
                "    }",
                "    return 0;",
                "}"
            ])
        case "html":
            return template([
                "<!doctype html>",
                "<html lang=\"en\">",
                "<head>",
                "  <meta charset=\"utf-8\" />",
                "  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />",
                "  <meta name=\"description\" content=\"A short page description\" />",
                "  <title>Page Title</title>",
                "  <link rel=\"stylesheet\" href=\"styles.css\" />",
                "</head>",
                "<body>",
                "  <main>",
                "    <h1>Page Title</h1>",
                "    <p>Start building here.</p>",
                "  </main>",
                "</body>",
                "</html>"
            ])
        case "expressionengine":
            return template([
                "{exp:channel:entries channel=\"news\" limit=\"10\" dynamic=\"no\"}",
                "  <article>",
                "    <h2><a href=\"{url_title_path='news'}\">{title}</a></h2>",
                "    <p>{summary}</p>",
                "  </article>",
                "  {if no_results}<p>No entries found.</p>{/if}",
                "{/exp:channel:entries}"
            ])
        case "css":
            return template([
                ":root {",
                "  color-scheme: light dark;",
                "  font-family: system-ui, sans-serif;",
                "  line-height: 1.5;",
                "}",
                "",
                "* {",
                "  box-sizing: border-box;",
                "}",
                "",
                "body {",
                "  margin: 0;",
                "  min-height: 100vh;",
                "}"
            ])
        case "sql":
            return template([
                "CREATE TABLE IF NOT EXISTS items (",
                "    id INTEGER PRIMARY KEY,",
                "    name TEXT NOT NULL,",
                "    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP",
                ");",
                "",
                "SELECT id, name, created_at",
                "FROM items",
                "ORDER BY created_at DESC;"
            ])
        case "markdown":
            return template([
                "# Project Title",
                "",
                "A concise description of the project.",
                "",
                "## Getting Started",
                "",
                "1. Install the requirements.",
                "2. Run the project.",
                "",
                "## Usage",
                "",
                "```text",
                "command --option",
                "```"
            ])
        case "tex":
            return template([
                "\\documentclass{article}",
                "\\usepackage[utf8]{inputenc}",
                "\\usepackage[T1]{fontenc}",
                "",
                "\\title{Document Title}",
                "\\author{Author Name}",
                "\\date{\\today}",
                "",
                "\\begin{document}",
                "\\maketitle",
                "",
                "\\section{Introduction}",
                "Start writing here.",
                "",
                "\\end{document}"
            ])
        case "yaml":
            return template([
                "name: example",
                "version: 1",
                "enabled: true",
                "options:",
                "  environment: development",
                "  retries: 3"
            ])
        case "json":
            return template([
                "{",
                "  \"name\": \"example\",",
                "  \"version\": 1,",
                "  \"enabled\": true,",
                "  \"options\": {",
                "    \"environment\": \"development\",",
                "    \"retries\": 3",
                "  }",
                "}"
            ])
        case "xml":
            return template([
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<configuration>",
                "  <name>example</name>",
                "  <version>1</version>",
                "  <enabled>true</enabled>",
                "</configuration>"
            ])
        case "toml":
            return template([
                "name = \"example\"",
                "version = 1",
                "enabled = true",
                "",
                "[options]",
                "environment = \"development\"",
                "retries = 3"
            ])
        case "nix":
            return template([
                "{ pkgs ? import <nixpkgs> {} }:",
                "",
                "pkgs.stdenv.mkDerivation {",
                "  pname = \"example\";",
                "  version = \"0.1.0\";",
                "",
                "  src = ./.;",
                "",
                "  buildPhase = ''",
                "    echo \"Build ${pname}-${version}\"",
                "  '';",
                "}"
            ])
        case "eml":
            return template([
                "From: Sender <sender@example.com>",
                "To: Recipient <recipient@example.com>",
                "Subject: Message subject",
                "Date: Sat, 25 Jul 2026 12:00:00 +0200",
                "Message-ID: <example-20260725@example.com>",
                "MIME-Version: 1.0",
                "Content-Type: text/plain; charset=UTF-8",
                "Content-Transfer-Encoding: 8bit",
                "",
                "Write the message body here."
            ])
        case "csv":
            return template([
                "id,name,status",
                "1,First item,active",
                "2,Second item,pending"
            ])
        case "ini":
            return template([
                "[application]",
                "name=example",
                "environment=development",
                "",
                "[logging]",
                "level=info"
            ])
        case "vim":
            return template([
                "\" Sensible editing defaults",
                "set number",
                "set expandtab",
                "set shiftwidth=4",
                "set softtabstop=4",
                "syntax enable"
            ])
        case "log":
            return template([
                "2026-01-01T12:00:00.000Z INFO  [app] Application started",
                "2026-01-01T12:00:00.084Z DEBUG [config] Configuration loaded",
                "2026-01-01T12:00:01.217Z INFO  [network] Listening on 127.0.0.1:8080",
                "2026-01-01T12:00:02.492Z WARN  [cache] Response exceeded 250 ms",
                "2026-01-01T12:00:02.861Z INFO  [cache] Retry completed",
                "{\"timestamp\":\"2026-01-01T12:00:03.105Z\",\"level\":\"error\",\"message\":\"Preview render failed\"}",
                "2026-01-01T12:00:03.411Z DEBUG [preview] Fallback renderer selected",
                "2026-01-01T12:00:03.709Z INFO  [app] Ready"
            ])
        case "crashlog":
            return template([
                "Process: ExampleApp [123]",
                "Path: /Applications/ExampleApp.app/Contents/MacOS/ExampleApp",
                "Identifier: com.example.ExampleApp",
                "Exception Type: EXC_BAD_ACCESS (SIGSEGV)",
                "Crashed Thread: 0",
                "",
                "Thread 0 Crashed:",
                "0   ExampleApp  0x0000000100000000 main + 12"
            ])
        case "ipynb":
            return template([
                "{",
                "  \"cells\": [",
                "    {",
                "      \"cell_type\": \"code\",",
                "      \"execution_count\": null,",
                "      \"metadata\": {},",
                "      \"outputs\": [],",
                "      \"source\": [\"print('Hello, World!')\"]",
                "    }",
                "  ],",
                "  \"metadata\": {},",
                "  \"nbformat\": 4,",
                "  \"nbformat_minor\": 5",
                "}"
            ])
        case "typst":
            return template([
                "#set page(margin: 2cm)",
                "#set text(font: \"Libertinus Serif\")",
                "",
                "= Typst document",
                "",
                "This is an AI-assisted Typst document.",
                "",
                "$ x^2 + y^2 = z^2 $"
            ])
        case "bash":
            return shellTemplate(interpreter: "bash")
        case "zsh":
            return shellTemplate(interpreter: "zsh")
        case "powershell":
            return template([
                "param(",
                "    [string]$Name = \"World\"",
                ")",
                "",
                "Set-StrictMode -Version Latest",
                "$ErrorActionPreference = \"Stop\"",
                "",
                "Write-Output \"Hello, $Name!\""
            ])
        case "standard":
            return template([
                "// Entry point",
                "function main() {",
                "    print(\"Hello, World!\")",
                "}",
                "",
                "main()"
            ])
        case "plain":
            return template([
                "Title",
                "",
                "Summary:",
                "",
                "Next steps:",
                "- "
            ])
        default:
            return nil
        }
    }

    private static func shellTemplate(interpreter: String) -> String {
        template([
            "#!/usr/bin/env \(interpreter)",
            "",
            "set -euo pipefail",
            "",
            "main() {",
            "  local name=\"${1:-World}\"",
            "  printf 'Hello, %s!\\n' \"$name\"",
            "}",
            "",
            "main \"$@\""
        ])
    }

    private static func template(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}

extension ContentView {
    func toggleAutoCompletion() {
        let willEnable = !isAutoCompletionEnabled
        if willEnable && viewModel.isBrainDumpMode {
            viewModel.isBrainDumpMode = false
            UserDefaults.standard.set(false, forKey: "BrainDumpModeEnabled")
        }
        isAutoCompletionEnabled.toggle()
        syncAppleCompletionAvailability()
        if willEnable {
            maybePromptForLanguageSetup()
        }
    }

    private func maybePromptForLanguageSetup() {
        guard currentLanguage == "plain" else { return }
        languagePromptSelection = currentLanguage == "plain" ? "plain" : currentLanguage
        languagePromptInsertTemplate = false
        showLanguageSetupPrompt = true
    }

    func syncAppleCompletionAvailability() {
        // Completion scheduling is the gate for Apple Foundation Models; AppleFM only checks system availability.
    }

    private func applyLanguageSelection(language: String, insertTemplate: Bool) {
        let contentIsEmpty = currentDocumentIsEmpty
        if let tab = viewModel.selectedTab {
            viewModel.updateTabLanguage(tabID: tab.id, language: language)
            if insertTemplate, contentIsEmpty, let template = starterTemplate(for: language) {
                viewModel.updateTabContent(tabID: tab.id, content: template)
            }
        } else {
            singleLanguage = language
            if insertTemplate, contentIsEmpty, let template = starterTemplate(for: language) {
                singleContent = template
            }
        }
    }

    var languageSetupSheet: some View {
        let contentIsEmpty = currentDocumentIsEmpty
        let canInsertTemplate = contentIsEmpty

        return VStack(alignment: .leading, spacing: 16) {
            Text("Choose a language for code completion")
                .font(.headline)
            Text("You can change this later from the Language picker.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Picker("Language", selection: $languagePromptSelection) {
                ForEach(languageOptions, id: \.self) { lang in
                    Text(languageLabel(for: lang)).tag(lang)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)

            if canInsertTemplate {
                Toggle("Insert starter template", isOn: $languagePromptInsertTemplate)
            }

            HStack {
                Button("Use Plain Text") {
                    applyLanguageSelection(language: "plain", insertTemplate: false)
                    showLanguageSetupPrompt = false
                }
                Spacer()
                Button("Use Selected Language") {
                    applyLanguageSelection(language: languagePromptSelection, insertTemplate: languagePromptInsertTemplate)
                    showLanguageSetupPrompt = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
    }

    var languageOptions: [String] {
        CodeTemplateCatalog.supportedLanguages
    }

    func languageLabel(for lang: String) -> String {
        switch lang {
        case "php": return "PHP"
        case "cobol": return "COBOL"
        case "dotenv": return "Dotenv"
        case "proto": return "Proto"
        case "graphql": return "GraphQL"
        case "rst": return "reStructuredText"
        case "nginx": return "Nginx"
        case "objective-c": return "Objective-C"
        case "csharp": return "C#"
        case "c": return "C"
        case "cpp": return "C++"
        case "json": return "JSON"
        case "xml": return "XML"
        case "yaml": return "YAML"
        case "toml": return "TOML"
        case "nix": return "Nix"
        case "eml": return "Email Message"
        case "csv": return "CSV"
        case "ini": return "INI"
        case "sql": return "SQL"
        case "vim": return "Vim"
        case "log": return "Log"
        case "crashlog": return "Apple Crash Report"
        case "ipynb": return "Jupyter Notebook"
        case "tex": return "TeX"
        case "html": return "HTML"
        case "expressionengine": return "ExpressionEngine"
        case "css": return "CSS"
        case "standard": return "Standard"
        default: return lang.capitalized
        }
    }

    /// Keeps the iPhone toolbar legible without changing the language names in
    /// its menu or accessibility value.
    func compactLanguageLabel(for lang: String) -> String {
        switch lang {
        case "markdown": return "MD"
        case "javascript": return "JS"
        case "typescript": return "TS"
        case "objective-c": return "Obj-C"
        case "csharp": return "C#"
        case "cpp": return "C++"
        case "dockerfile": return "Docker"
        case "makefile": return "Make"
        case "expressionengine": return "EE"
        case "crashlog": return "Crash"
        case "ipynb": return "Jupyter"
        case "plain": return "Text"
        default: return lang.uppercased()
        }
    }

    func toolbarLanguageLabel(for lang: String) -> String {
#if os(iOS)
        compactLanguageLabel(for: lang)
#else
        languageLabel(for: lang)
#endif
    }

    private func normalizedLanguageSearchToken(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    func presentLanguageSearchSheet() {
        showLanguageSearchSheet = true
    }

    var languageSearchSheet: some View {
        LanguageSearchSheetView(
            languageOptions: languageOptions,
            selectedLanguage: currentLanguagePickerBinding,
            isPresented: $showLanguageSearchSheet,
            languageLabel: languageLabel(for:),
            normalizeToken: normalizedLanguageSearchToken(_:),
            translucentBackgroundEnabled: enableTranslucentWindow,
            surfaceBackgroundStyle: editorSurfaceBackgroundStyle
        )
#if os(iOS) || os(visionOS)
        .presentationDetents([.medium, .large])
        .presentationBackground(editorSurfaceBackgroundStyle)
#endif
    }

    private struct LanguageSearchSheetView: View {
        let languageOptions: [String]
        @Binding var selectedLanguage: String
        @Binding var isPresented: Bool
        let languageLabel: (String) -> String
        let normalizeToken: (String) -> String
        let translucentBackgroundEnabled: Bool
        let surfaceBackgroundStyle: AnyShapeStyle
        @Environment(\.colorScheme) private var colorScheme
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @FocusState private var searchFieldFocused: Bool
        @AppStorage("RecentLanguageSelections") private var recentLanguageIDsRaw: String = ""
        @State private var query: String = ""
        private let suggestedLanguageIDs = ["markdown", "python", "swift", "json", "javascript", "typescript"]

        private var recentLanguageIDs: [String] {
            recentLanguageIDsRaw.split(separator: ",").map(String.init).filter { languageOptions.contains($0) }
        }

        private var isCompactLayout: Bool { horizontalSizeClass == .compact }

        private var gridColumns: [GridItem] {
            isCompactLayout
                ? [GridItem(.flexible(), spacing: 10)]
                : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        }

        private var maxPanelContentWidth: CGFloat { isCompactLayout ? .infinity : 600 }

        private var filteredLanguageOptions: [String] {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedQuery.isEmpty else { return languageOptions }
            let normalizedQuery = normalizeToken(trimmedQuery)
            guard !normalizedQuery.isEmpty else { return languageOptions }

            return languageOptions.filter { lang in
                let label = languageLabel(lang)
                if lang.localizedCaseInsensitiveContains(trimmedQuery) || label.localizedCaseInsensitiveContains(trimmedQuery) {
                    return true
                }
                return normalizeToken(lang).contains(normalizedQuery) || normalizeToken(label).contains(normalizedQuery)
            }
        }

        private var suggestedLanguages: [String] {
            uniqueLanguages(recentLanguageIDs + suggestedLanguageIDs)
                .filter { filteredLanguageOptions.contains($0) }
        }

        private var otherLanguages: [String] {
            filteredLanguageOptions.filter { !suggestedLanguages.contains($0) }
        }

        private func selectLanguage(_ language: String) {
            recentLanguageIDsRaw = uniqueLanguages([language] + recentLanguageIDs).prefix(6).joined(separator: ",")
            selectedLanguage = language
            isPresented = false
        }

        private func uniqueLanguages(_ languages: [String]) -> [String] {
            var seen = Set<String>()
            return languages.filter { seen.insert($0).inserted }
        }

        private func languageSubtitle(_ language: String) -> String {
            switch language {
            case "markdown": return ".md"
            case "python": return ".py"
            case "swift": return ".swift"
            case "javascript": return ".js"
            case "typescript": return ".ts"
            case "json": return ".json"
            case "yaml": return ".yml / .yaml"
            case "plain": return "No syntax highlighting"
            default: return language == selectedLanguage ? "Current language" : ""
            }
        }

        @ViewBuilder
        private func languageRow(_ language: String) -> some View {
            Button { selectLanguage(language) } label: {
                HStack(spacing: 10) {
                    Image(systemName: language == selectedLanguage ? "checkmark.circle.fill" : "textformat")
                        .foregroundStyle(language == selectedLanguage ? NeonUIStyle.accentBlue : .secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(languageLabel(language)).foregroundStyle(.primary).lineLimit(1)
                        let subtitle = languageSubtitle(language)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if language == selectedLanguage {
                        Text("Selected")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(NeonUIStyle.accentBlue)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(language == selectedLanguage ? AnyShapeStyle(NeonUIStyle.accentBlue.opacity(0.14)) : AnyShapeStyle(Color.clear))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(languageLabel(language))
            .accessibilityAddTraits(language == selectedLanguage ? .isSelected : [])
        }

        @ViewBuilder
        private func languageSection(_ title: String, languages: [String]) -> some View {
            if !languages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                        ForEach(languages, id: \.self) { language in
                            languageRow(language)
                        }
                    }
                }
            }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(NSLocalizedString("Select Language", comment: "Language search sheet title"))
                            .font(.title2.weight(.semibold))
                        Text("Choose syntax highlighting for this file")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Search language", comment: "Language search field placeholder"), text: $query)
#if os(macOS)
                        .textFieldStyle(.plain)
#endif
                        .focused($searchFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            if filteredLanguageOptions.count == 1, let language = filteredLanguageOptions.first {
                                selectLanguage(language)
                            }
                        }
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(NSLocalizedString("Clear search", comment: "Language search clear button accessibility label"))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: maxPanelContentWidth)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(translucentBackgroundEnabled ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color.secondary.opacity(colorScheme == .dark ? 0.22 : 0.12)))
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if filteredLanguageOptions.isEmpty {
                            Label(NSLocalizedString("No language found", comment: "Language search empty state"), systemImage: "magnifyingglass")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 100)
                        } else {
                            languageSection("Suggested", languages: suggestedLanguages)
                            languageSection("All Languages", languages: otherLanguages)
                        }
                    }
                    .frame(maxWidth: maxPanelContentWidth, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, minHeight: isCompactLayout ? 280 : 300, maxHeight: 430)
            }
            .padding(isCompactLayout ? 18 : 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#if os(macOS)
            .frame(width: 680, height: 560, alignment: .center)
#endif
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(translucentBackgroundEnabled ? AnyShapeStyle(.ultraThinMaterial) : surfaceBackgroundStyle)
            )
            .padding(10)
        }
    }

    private func starterTemplate(for language: String) -> String? {
        if let override = UserDefaults.standard.string(forKey: CodeTemplateCatalog.overrideKey(for: language)),
           !override.isEmpty {
            return override
        }
        return CodeTemplateCatalog.defaultTemplate(for: language)
    }

    func insertTemplateForCurrentLanguage() {
        let language = currentLanguage
        guard let template = starterTemplate(for: language) else { return }
        editorExternalMutationRevision &+= 1
        let sourceContent = liveEditorBufferText() ?? currentContentBinding.wrappedValue
        let updated: String
        if sourceContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated = template
        } else {
            updated = sourceContent + (sourceContent.hasSuffix("\n") ? "\n" : "\n\n") + template
        }
        currentContentBinding.wrappedValue = updated
    }

    private func detectLanguageWithAppleIntelligence(_ text: String) async -> String {
        // Supported languages in our picker
        let supported = ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "fish", "perl", "lua", "r", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "dockerfile", "makefile", "hcl", "xcconfig", "strings", "objective-c", "csharp", "json", "xml", "yaml", "toml", "nix", "eml", "csv", "ini", "vim", "log", "crashlog", "ipynb", "markdown", "tex", "bash", "zsh", "powershell", "standard", "plain"]

        #if USE_FOUNDATION_MODELS && canImport(FoundationModels)
        // Attempt a lightweight model-based detection via AppleIntelligenceAIClient if available
        do {
            let client = AppleIntelligenceAIClient()
            var response = ""
            for await chunk in client.streamSuggestions(prompt: "Detect the programming or markup language of the following snippet and answer with one of: \(supported.joined(separator: ", ")). If none match, reply with 'swift'.\n\nSnippet:\n\n\(text)\n\nAnswer:") {
                response += chunk
            }
            let detectedRaw = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased()
            if let match = supported.first(where: { detectedRaw.contains($0) }) {
                return match
            }
        }
        #endif

        // Heuristic fallback
        let lower = text.lowercased()
        // Normalize common C# indicators to "csharp" to ensure the picker has a matching tag
        if lower.contains("c#") || lower.contains("c sharp") || lower.range(of: #"\bcs\b"#, options: .regularExpression) != nil || lower.contains(".cs") {
            return "csharp"
        }
        if lower.contains("<?php") || lower.contains("<?=") || lower.contains("$this->") || lower.contains("$_get") || lower.contains("$_post") || lower.contains("$_server") {
            return "php"
        }
        if lower.range(of: #"\{/?exp:[A-Za-z0-9_:-]+[^}]*\}"#, options: .regularExpression) != nil ||
            lower.range(of: #"\{if(?::elseif)?\b[^}]*\}|\{\/if\}|\{:else\}"#, options: .regularExpression) != nil ||
            lower.range(of: #"\{!--[\s\S]*?--\}"#, options: .regularExpression) != nil {
            return "expressionengine"
        }
        if lower.contains("syntax = \"proto") || lower.contains("message ") || (lower.contains("enum ") && lower.contains("rpc ")) {
            return "proto"
        }
        if lower.contains("type query") || lower.contains("schema {") || (lower.contains("interface ") && lower.contains("implements ")) {
            return "graphql"
        }
        if lower.contains("server {") || lower.contains("http {") || lower.contains("location /") {
            return "nginx"
        }
        if lower.contains(".. code-block::") || lower.contains(".. toctree::") || (lower.contains("::") && lower.contains("\n====")) {
            return "rst"
        }
        if lower.contains("\\documentclass")
            || lower.contains("\\usepackage")
            || lower.contains("\\begin{document}")
            || lower.contains("\\end{document}") {
            return "tex"
        }
        if lower.contains("\n") && lower.range(of: #"(?m)^[A-Z_][A-Z0-9_]*=.*$"#, options: .regularExpression) != nil {
            return "dotenv"
        }
        if lower.contains("identification division") || lower.contains("procedure division") || lower.contains("working-storage section") || lower.contains("environment division") {
            return "cobol"
        }
        if text.contains(",") && text.contains("\n") {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            if lines.count >= 2 {
                let commaCounts = lines.prefix(6).map { line in line.filter { $0 == "," }.count }
                if let firstCount = commaCounts.first, firstCount > 0 && commaCounts.dropFirst().allSatisfy({ $0 == firstCount || abs($0 - firstCount) <= 1 }) {
                    return "csv"
                }
            }
        }
        // C# strong heuristic
        if lower.contains("using system") || lower.contains("namespace ") || lower.contains("public class") || lower.contains("public static void main") || lower.contains("static void main") || lower.contains("console.writeline") || lower.contains("console.readline") || lower.contains("class program") || lower.contains("get; set;") || lower.contains("list<") || lower.contains("dictionary<") || lower.contains("ienumerable<") || lower.range(of: #"\[[A-Za-z_][A-Za-z0-9_]*\]"#, options: .regularExpression) != nil {
            return "csharp"
        }
        if lower.contains("import swift") || lower.contains("struct ") || lower.contains("func ") {
            return "swift"
        }
        if lower.contains("def ") || (lower.contains("class ") && lower.contains(":")) {
            return "python"
        }
        if lower.contains("function ") || lower.contains("const ") || lower.contains("let ") || lower.contains("=>") {
            return "javascript"
        }
        // XML
        if lower.contains("<?xml") || (lower.contains("</") && lower.contains(">")) {
            return "xml"
        }
        // YAML
        if lower.contains(": ") && (lower.contains("- ") || lower.contains("\n  ")) && !lower.contains(";") {
            return "yaml"
        }
        // TOML / INI
        if lower.range(of: #"^\[[^\]]+\]"#, options: [.regularExpression, .anchored]) != nil || (lower.contains("=") && lower.contains("\n[")) {
            return lower.contains("toml") ? "toml" : "ini"
        }
        // SQL
        if lower.range(of: #"\b(select|insert|update|delete|create\s+table|from|where|join)\b"#, options: .regularExpression) != nil {
            return "sql"
        }
        // Go
        if lower.contains("package ") && lower.contains("func ") {
            return "go"
        }
        // Java
        if lower.contains("public class") || lower.contains("public static void main") {
            return "java"
        }
        // Kotlin
        if (lower.contains("fun ") || lower.contains("val ")) || (lower.contains("var ") && lower.contains(":")) {
            return "kotlin"
        }
        // TypeScript
        if lower.contains("interface ") || (lower.contains("type ") && lower.contains(":")) || lower.contains(": string") {
            return "typescript"
        }
        // Ruby
        if lower.contains("def ") || (lower.contains("end") && lower.contains("class ")) {
            return "ruby"
        }
        // Rust
        if lower.contains("fn ") || lower.contains("let mut ") || lower.contains("pub struct") {
            return "rust"
        }
        // Objective-C
        if lower.contains("@interface") || lower.contains("@implementation") || lower.contains("#import ") {
            return "objective-c"
        }
        // INI
        if lower.range(of: #"^;.*$"#, options: .regularExpression) != nil || lower.range(of: #"^\w+\s*=\s*.*$"#, options: .regularExpression) != nil {
            return "ini"
        }
        if lower.contains("<html") || lower.contains("<div") || lower.contains("</") {
            return "html"
        }
        // Stricter C-family detection to avoid misclassifying C#
        if lower.contains("#include") || lower.range(of: #"^\s*(int|void)\s+main\s*\("#, options: .regularExpression) != nil {
            return "cpp"
        }
        if lower.contains("class ") && (lower.contains("::") || lower.contains("template<")) {
            return "cpp"
        }
        if lower.contains(";") && lower.contains(":") && lower.contains("{") && lower.contains("}") && lower.contains("color:") {
            return "css"
        }
        // Shell detection (bash/zsh)
        if lower.contains("#!/bin/bash") || lower.contains("#!/usr/bin/env bash") || lower.contains("declare -a") || lower.contains("[[ ") || lower.contains(" ]] ") || lower.contains("$(") {
            return "bash"
        }
        if lower.contains("#!/bin/zsh") || lower.contains("#!/usr/bin/env zsh") || lower.contains("typeset ") || lower.contains("autoload -Uz") || lower.contains("setopt ") {
            return "zsh"
        }
        // Generic POSIX sh fallback
        if lower.contains("#!/bin/sh") || lower.contains("#!/usr/bin/env sh") || lower.contains(" fi") || lower.contains(" do") || lower.contains(" done") || lower.contains(" esac") {
            return "bash"
        }
        // PowerShell detection
        if lower.contains("write-host") || lower.contains("param(") || lower.contains("$psversiontable") || lower.range(of: #"\b(Get|Set|New|Remove|Add|Clear|Write)-[A-Za-z]+\b"#, options: .regularExpression) != nil {
            return "powershell"
        }
        return "standard"
    }

}

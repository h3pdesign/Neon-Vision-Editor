import SwiftUI
import Foundation
#if USE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

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
        let contentIsEmpty = currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        let contentIsEmpty = currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "tex", "bash", "zsh", "powershell", "standard", "plain"]
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
        case "csv": return "CSV"
        case "ini": return "INI"
        case "sql": return "SQL"
        case "vim": return "Vim"
        case "log": return "Log"
        case "ipynb": return "Jupyter Notebook"
        case "tex": return "TeX"
        case "html": return "HTML"
        case "expressionengine": return "ExpressionEngine"
        case "css": return "CSS"
        case "standard": return "Standard"
        default: return lang.capitalized
        }
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
        @State private var query: String = ""
        private let maxPanelContentWidth: CGFloat = 440

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

        var body: some View {
            VStack(spacing: 18) {
                Text(NSLocalizedString("Select Language", comment: "Language search sheet title"))
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(NSLocalizedString("Search language", comment: "Language search field placeholder"), text: $query)
#if os(macOS)
                        .textFieldStyle(.plain)
#endif
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
                    LazyVStack(spacing: 8) {
                        if filteredLanguageOptions.isEmpty {
                            Text(NSLocalizedString("No language found", comment: "Language search empty state"))
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 22)
                        } else {
                            ForEach(filteredLanguageOptions, id: \.self) { lang in
                                Button {
                                    selectedLanguage = lang
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(languageLabel(lang))
                                            .foregroundStyle(.primary)
                                        Spacer(minLength: 8)
                                        if selectedLanguage == lang {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(NeonUIStyle.accentBlue)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: maxPanelContentWidth, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(selectedLanguage == lang ? AnyShapeStyle(NeonUIStyle.accentBlue.opacity(0.14)) : AnyShapeStyle(Color.clear))
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(languageLabel(lang))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .frame(minHeight: 160, maxHeight: 230)

                HStack {
                    Spacer()
                    Button(NSLocalizedString("Close", comment: "Close language search sheet")) { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
#if os(macOS)
            .frame(width: 560, height: 340, alignment: .center)
#endif
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(translucentBackgroundEnabled ? AnyShapeStyle(.ultraThinMaterial) : surfaceBackgroundStyle)
            )
            .padding(10)
        }
    }

    private func starterTemplate(for language: String) -> String? {
        if let override = UserDefaults.standard.string(forKey: templateOverrideKey(for: language)),
           !override.isEmpty {
            return override
        }
        switch language {
        case "swift":
            return "import Foundation\n\n// TODO: Add code here\n"
        case "python":
            return "def main():\n    pass\n\n\nif __name__ == \"__main__\":\n    main()\n"
        case "javascript":
            return "\"use strict\";\n\nfunction main() {\n  // TODO: Add code here\n}\n\nmain();\n"
        case "typescript":
            return "function main(): void {\n  // TODO: Add code here\n}\n\nmain();\n"
        case "java":
            return "public class Main {\n    public static void main(String[] args) {\n        // TODO: Add code here\n    }\n}\n"
        case "kotlin":
            return "fun main() {\n    // TODO: Add code here\n}\n"
        case "go":
            return "package main\n\nimport \"fmt\"\n\nfunc main() {\n    fmt.Println(\"Hello\")\n}\n"
        case "ruby":
            return "def main\n  # TODO: Add code here\nend\n\nmain\n"
        case "rust":
            return "fn main() {\n    // TODO: Add code here\n}\n"
        case "php":
            return "<?php\n\n// TODO: Add code here\n"
        case "cobol":
            return "       IDENTIFICATION DIVISION.\n       PROGRAM-ID. MAIN.\n\n       PROCEDURE DIVISION.\n           DISPLAY \"TODO\".\n           STOP RUN.\n"
        case "dotenv":
            return "# TODO=VALUE\n"
        case "proto":
            return "syntax = \"proto3\";\n\npackage example;\n\nmessage Example {\n  string id = 1;\n}\n"
        case "graphql":
            return "type Query {\n  hello: String\n}\n"
        case "rst":
            return "Title\n=====\n\nWrite here.\n"
        case "nginx":
            return "server {\n    listen 80;\n    server_name example.com;\n\n    location / {\n        return 200 \"TODO\";\n    }\n}\n"
        case "c":
            return "#include <stdio.h>\n\nint main(void) {\n    // TODO: Add code here\n    return 0;\n}\n"
        case "cpp":
            return "#include <iostream>\n\nint main() {\n    // TODO: Add code here\n    return 0;\n}\n"
        case "csharp":
            return "using System;\n\npublic class Program {\n    public static void Main(string[] args) {\n        // TODO: Add code here\n    }\n}\n"
        case "objective-c":
            return "#import <Foundation/Foundation.h>\n\nint main(int argc, const char * argv[]) {\n    @autoreleasepool {\n        // TODO: Add code here\n    }\n    return 0;\n}\n"
        case "html":
            return "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\" />\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />\n  <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>\n"
        case "expressionengine":
            return "{exp:channel:entries channel=\"news\" limit=\"10\"}\n  <article>\n    <h2>{title}</h2>\n    <p>{summary}</p>\n  </article>\n{/exp:channel:entries}\n"
        case "css":
            return "/* TODO: Add styles here */\n\nbody {\n  margin: 0;\n}\n"
        case "sql":
            return "-- TODO: Add queries here\n"
        case "markdown":
            return "# Title\n\nWrite here.\n"
        case "tex":
            return "\\documentclass{article}\n\\usepackage[utf8]{inputenc}\n\n\\begin{document}\n\\section{Title}\n\nTODO\n\n\\end{document}\n"
        case "yaml":
            return "# TODO: Add config here\n"
        case "json":
            return "{\n  \"todo\": true\n}\n"
        case "xml":
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n  <todo>true</todo>\n</root>\n"
        case "toml":
            return "# TODO = \"value\"\n"
        case "csv":
            return "col1,col2\nvalue1,value2\n"
        case "ini":
            return "[section]\nkey=value\n"
        case "vim":
            return "\" TODO: Add vim config here\n"
        case "log":
            return "INFO: TODO\n"
        case "ipynb":
            return "{\n  \"cells\": [],\n  \"metadata\": {},\n  \"nbformat\": 4,\n  \"nbformat_minor\": 5\n}\n"
        case "bash":
            return "#!/usr/bin/env bash\n\nset -euo pipefail\n\n# TODO: Add script here\n"
        case "zsh":
            return "#!/usr/bin/env zsh\n\nset -euo pipefail\n\n# TODO: Add script here\n"
        case "powershell":
            return "# TODO: Add script here\n"
        case "standard":
            return "// TODO: Add code here\n"
        case "plain":
            return "TODO\n"
        default:
            return "TODO\n"
        }
    }

    private func templateOverrideKey(for language: String) -> String {
        "TemplateOverride_\(language)"
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
        let supported = ["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "objective-c", "csharp", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "tex", "bash", "zsh", "powershell", "standard", "plain"]

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

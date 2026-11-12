import Foundation

/// MeierScript 0.5.2 vocabulary and CLI diagnostics helpers.
///
/// The vocabulary follows the ScriptingSDKit documentation shipped inside
/// SidUI Editor/SidUI Viewer and the CLI's own `getCommands()` list. This file
/// is platform agnostic; running scripts is macOS-only (`MeierScriptRunner`).
nonisolated enum MeierScriptLanguage {
    static let identifier = "meierscript"
    static let fileExtension = "meierscript"
    static let displayName = "MeierScript"

    static let keywords: [String] = [
        "var", "let", "staticLet", "globalVar", "func", "return",
        "if", "else", "guard", "while", "for", "in", "switch", "case", "default", "break",
        "detach"
    ]

    static let constants: [String] = ["true", "false", "nil"]

    static let typeNames: [String] = ["String", "Int", "Double", "Number", "Bool", "Boolean", "Any"]

    /// Interpreter-provided variables and constants.
    static let reservedVariables: [String] = [
        "ARGUMENTS", "ERRORCODE", "ERRORTEXT", "ERRORCONFIG", "ERRORHANDLER", "SCRIPTCONTENT"
    ]

    /// Built-in functions reported by `getCommands()` in meierscript 0.5.2.
    static let builtins: [String] = [
        "appType", "append", "array", "bool", "char", "commandExists", "compareVersions", "components",
        "contains", "copyFromClipboard", "copyToClipboard", "count", "createPassword", "createRandomString",
        "date", "dateFormat", "dateIntervalSince1970", "decodeBase64", "decodeJSON", "decryptParameter",
        "deleteFile", "disableLimitations", "disableRecursionBudget", "double", "dropFirst", "dropLast",
        "encodeBase64", "encodeJSON", "encryptParameter", "exit", "exitOnError", "fileExists", "filter",
        "first", "getAssertions", "getAssertionsStatus", "getCommands", "getDiskInformation", "getEnv",
        "getGlobalVariables", "getPreference", "getScreenInformation", "getSystemInformation", "getVariable",
        "getVariables", "ifEqual", "ifNotEqual", "ifNotNil", "include", "indices", "int", "isEmpty", "isNil",
        "isNotEmpty", "isNotNil", "isVariable", "join", "keys", "last", "lowercase", "map", "max", "md5Hash",
        "min", "number", "openApp", "openUrl", "print", "printError", "readFile", "readFromURL", "readLine",
        "remove", "removePreference", "replace", "reverse", "round", "runCommand", "setPreference",
        "setVariable", "sha256Hash", "sleep", "sort", "split", "splitPath", "startsWith", "string",
        "subString", "throw", "throwOnError", "toggle", "triggerLogout", "triggerRebootDialog", "trim",
        "typeOf", "uppercase", "writeFile"
    ]

    /// Words offered by local completion, in priority order and without duplicates.
    static let completionVocabulary: [String] = {
        var seen = Set<String>()
        return (keywords + builtins + typeNames + constants + reservedVariables).filter { seen.insert($0).inserted }
    }()

    // MARK: - Syntax check

    /// The CLI parses the whole script before executing it. A leading `exit()`
    /// therefore reports every parser/lexer error without running any statement.
    static let syntaxCheckPrelude = "exit()\n"

    static func syntaxCheckSource(for source: String) -> String {
        syntaxCheckPrelude + source
    }

    /// Positions in CLI messages ("at 4:1") refer to the submitted source. For a
    /// syntax check, shift them back by the prelude so they match the editor.
    static func remapSyntaxCheckDiagnostics(_ message: String, lineOffset: Int = 1) -> String {
        guard lineOffset != 0,
              let regex = try? NSRegularExpression(pattern: #"\bat (\d+):(\d+)"#) else { return message }
        let nsMessage = message as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: message, range: NSRange(location: 0, length: nsMessage.length)) {
            guard let line = Int(nsMessage.substring(with: match.range(at: 1))) else { continue }
            result += nsMessage.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let column = nsMessage.substring(with: match.range(at: 2))
            result += "at \(max(1, line - lineOffset)):\(column)"
            cursor = NSMaxRange(match.range)
        }
        result += nsMessage.substring(from: cursor)
        return result
    }

    struct Diagnostic: Equatable, Sendable {
        let line: Int
        let column: Int
        let message: String
    }

    /// Extracts the first "… at line:column: …" position from CLI error output.
    static func firstDiagnostic(in errorOutput: String) -> Diagnostic? {
        guard let regex = try? NSRegularExpression(pattern: #"(?m)^(.*?)\bat (\d+):(\d+):?\s*(.*)$"#) else { return nil }
        let nsOutput = errorOutput as NSString
        guard let match = regex.firstMatch(in: errorOutput, range: NSRange(location: 0, length: nsOutput.length)),
              let line = Int(nsOutput.substring(with: match.range(at: 2))),
              let column = Int(nsOutput.substring(with: match.range(at: 3))) else { return nil }
        let kind = nsOutput.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let detail = nsOutput.substring(with: match.range(at: 4)).trimmingCharacters(in: .whitespaces)
        let message = [kind, detail].filter { !$0.isEmpty }.joined(separator: " ")
        return Diagnostic(line: line, column: column, message: message)
    }
}

#if os(macOS)
import Foundation

/// Installed interpreters the run console can use for a document language.
/// Nothing is bundled or downloaded: each interpreter is looked up in the
/// usual install locations (Homebrew, the Xcode developer tools, the system).
/// Unsaved edits run as they are in the editor, through stdin or a private
/// temporary file, depending on what the tool accepts.
nonisolated struct ScriptInterpreter: Equatable, Sendable {
    /// How the script text reaches the tool.
    enum Input: Equatable, Sendable {
        /// Written to stdin.
        case standardInput
        /// Written to `script.<ext>` in a private temporary folder whose path
        /// replaces `filePlaceholder`; for tools that only accept files.
        case temporaryFile(fileExtension: String)
    }

    struct Command: Equatable, Sendable {
        var executableNames: [String]
        var arguments: [String]
        var input: Input
    }

    static let filePlaceholder = "{file}"
    static let temporaryFileStem = "script"

    let languageID: String
    let displayName: String
    let run: Command
    let syntaxCheck: Command?
    /// Captures the 1-based line of the first syntax error in group 1.
    let diagnosticLinePattern: String?

    var supportsSyntaxCheck: Bool { syntaxCheck != nil }

    static let all: [ScriptInterpreter] = [
        ScriptInterpreter(
            languageID: "python", displayName: "Python",
            run: Command(executableNames: ["python3"], arguments: ["-u", "-"], input: .standardInput),
            syntaxCheck: Command(executableNames: ["python3"],
                                 arguments: ["-c", "import sys; compile(sys.stdin.read(), '<stdin>', 'exec')"],
                                 input: .standardInput),
            diagnosticLinePattern: #"File "<stdin>", line (\d+)"#),
        ScriptInterpreter(
            languageID: "javascript", displayName: "JavaScript",
            run: Command(executableNames: ["node"], arguments: ["-"], input: .standardInput),
            syntaxCheck: Command(executableNames: ["node"], arguments: ["--check", "-"], input: .standardInput),
            diagnosticLinePattern: #"\[stdin\]:(\d+)"#),
        ScriptInterpreter(
            languageID: "ruby", displayName: "Ruby",
            run: Command(executableNames: ["ruby"], arguments: ["-"], input: .standardInput),
            syntaxCheck: Command(executableNames: ["ruby"], arguments: ["-c", "-"], input: .standardInput),
            diagnosticLinePattern: #"(?m)(?:^|\s)-:(\d+):"#),
        ScriptInterpreter(
            languageID: "perl", displayName: "Perl",
            run: Command(executableNames: ["perl"], arguments: ["-"], input: .standardInput),
            // No check: `perl -c` runs BEGIN and CHECK blocks, so Auto-Check
            // would execute document code without Run.
            syntaxCheck: nil, diagnosticLinePattern: nil),
        ScriptInterpreter(
            languageID: "php", displayName: "PHP",
            run: Command(executableNames: ["php"], arguments: [], input: .standardInput),
            syntaxCheck: Command(executableNames: ["php"], arguments: ["-l"], input: .standardInput),
            diagnosticLinePattern: #"on line (\d+)"#),
        ScriptInterpreter(
            languageID: "lua", displayName: "Lua",
            run: Command(executableNames: ["lua"], arguments: ["-"], input: .standardInput),
            syntaxCheck: Command(executableNames: ["luac"], arguments: ["-p", "-"], input: .standardInput),
            diagnosticLinePattern: #"stdin:(\d+):"#),
        ScriptInterpreter(
            languageID: "r", displayName: "R",
            run: Command(executableNames: ["Rscript"], arguments: ["-"], input: .standardInput),
            syntaxCheck: Command(executableNames: ["Rscript"],
                                 arguments: ["-e", "invisible(parse(file('stdin')))"], input: .standardInput),
            diagnosticLinePattern: #"\b(\d+):\d+: unexpected"#),
        // Shells read the script from a file: from stdin, `read` would consume
        // the script itself, and Bash 3.2 miscounts lines of `-c` strings.
        ScriptInterpreter(
            languageID: "bash", displayName: "Bash",
            run: Command(executableNames: ["bash"], arguments: [filePlaceholder], input: .temporaryFile(fileExtension: "sh")),
            syntaxCheck: Command(executableNames: ["bash"], arguments: ["-n", filePlaceholder],
                                 input: .temporaryFile(fileExtension: "sh")),
            diagnosticLinePattern: #"line (\d+):"#),
        ScriptInterpreter(
            languageID: "zsh", displayName: "Zsh",
            run: Command(executableNames: ["zsh"], arguments: [filePlaceholder], input: .temporaryFile(fileExtension: "zsh")),
            syntaxCheck: Command(executableNames: ["zsh"], arguments: ["-n", filePlaceholder],
                                 input: .temporaryFile(fileExtension: "zsh")),
            diagnosticLinePattern: #"script\.zsh:(\d+):"#),
        ScriptInterpreter(
            languageID: "fish", displayName: "Fish",
            run: Command(executableNames: ["fish"], arguments: ["--no-config", filePlaceholder],
                         input: .temporaryFile(fileExtension: "fish")),
            syntaxCheck: Command(executableNames: ["fish"], arguments: ["--no-config", "--no-execute", filePlaceholder],
                                 input: .temporaryFile(fileExtension: "fish")),
            diagnosticLinePattern: #"\(line (\d+)\)"#),
        ScriptInterpreter(
            languageID: "powershell", displayName: "PowerShell",
            run: Command(executableNames: ["pwsh"],
                         arguments: ["-NoLogo", "-NoProfile", "-NonInteractive", "-File", filePlaceholder],
                         input: .temporaryFile(fileExtension: "ps1")),
            syntaxCheck: nil, diagnosticLinePattern: nil),
        ScriptInterpreter(
            languageID: "swift", displayName: "Swift",
            run: Command(executableNames: ["swift"], arguments: [filePlaceholder],
                         input: .temporaryFile(fileExtension: "swift")),
            syntaxCheck: Command(executableNames: ["swiftc"], arguments: ["-parse", filePlaceholder],
                                 input: .temporaryFile(fileExtension: "swift")),
            diagnosticLinePattern: #"\.swift:(\d+):\d+: error"#),
    ]

    static func forLanguage(_ languageID: String) -> ScriptInterpreter? {
        let id = languageID.lowercased()
        return all.first { $0.languageID == id }
    }

    // MARK: - Locating tools

    /// Searched before the inherited `PATH`, which is minimal for apps opened
    /// from the Finder.
    static let preferredSearchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    static let systemSearchDirectories = ["/usr/bin", "/bin"]
    /// Real tool locations behind the `/usr/bin` xcrun shims. The shims are
    /// skipped: they do not work in the App Sandbox and, without developer
    /// tools, ask to install them.
    static let developerToolDirectories = [
        "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin",
        "/Applications/Xcode.app/Contents/Developer/usr/bin",
        "/Library/Developer/CommandLineTools/usr/bin",
    ]
    static let developerToolShims: Set<String> = ["python3", "swift", "swiftc"]

    static func searchDirectories(inheritedPath: String?) -> [String] {
        let inherited = (inheritedPath ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (preferredSearchDirectories + inherited + developerToolDirectories + systemSearchDirectories)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// First executable named `name`, skipping `/usr/bin` developer-tool shims.
    static func locate(
        _ name: String,
        directories: [String],
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        for directory in directories {
            if directory == "/usr/bin", developerToolShims.contains(name) { continue }
            let path = (directory as NSString).appendingPathComponent(name)
            if isExecutable(path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Resolves the tool for `command`. Python honors the interpreter chosen in
    /// Settings and a `.venv`/`venv` next to the document.
    func locate(_ command: Command, workingDirectory: URL?,
                defaults: UserDefaults = .standard,
                environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default
        if languageID == "python" {
            let preferred = (defaults.string(forKey: SettingsPreferenceKey.pythonInterpreterPath) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates = preferred.isEmpty ? [] : [NSString(string: preferred).expandingTildeInPath]
            if let workingDirectory {
                candidates += [".venv/bin/python3", ".venv/bin/python", "venv/bin/python3", "venv/bin/python"]
                    .map { workingDirectory.appendingPathComponent($0).path }
            }
            if let path = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
                return URL(fileURLWithPath: path)
            }
        }
        let directories = Self.searchDirectories(inheritedPath: environment["PATH"])
        for name in command.executableNames {
            if let url = Self.locate(name, directories: directories) { return url }
        }
        return nil
    }

    /// Environment for the child: the inherited one with Homebrew first on
    /// `PATH`, so tools the script starts are found as in Terminal.
    static func childEnvironment(_ inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = inherited
        let directories = (preferredSearchDirectories + (inherited["PATH"] ?? "").split(separator: ":").map(String.init)
            + systemSearchDirectories)
        var seen = Set<String>()
        environment["PATH"] = directories.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return environment
    }

    /// The macOS SDK next to a developer tool. In the sandbox the Swift driver
    /// cannot ask `xcrun` for it and fails to load the standard library.
    static func sdkRoot(forToolAt url: URL,
                        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        let path = url.path
        let candidate: String
        if let range = path.range(of: "/Contents/Developer/") {
            candidate = String(path[..<range.upperBound]) + "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
        } else if path.hasPrefix("/Library/Developer/CommandLineTools/") {
            candidate = "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
        } else {
            return nil
        }
        return exists(candidate) ? candidate : nil
    }

    // MARK: - Running

    /// Arguments with the placeholders filled in. Pure for tests.
    static func arguments(for command: Command, fileURL: URL?) -> [String] {
        command.arguments.map { $0 == filePlaceholder ? (fileURL?.path ?? $0) : $0 }
    }

    /// Node reads stdin as CommonJS, so `node --check -` rejects `import`
    /// and `export` that a `.mjs` file or a `"type": "module"` package allows.
    static func looksLikeESModule(_ source: String) -> Bool {
        source.range(of: #"(?m)^[ \t]*(import[ \t]*[\w{*"']|export[ \t]+[\w{*])"#, options: .regularExpression) != nil
    }

    func execute(source: String, mode: MeierScriptRunner.Mode, executableURL: URL,
                 workingDirectory: URL?, timeout: TimeInterval) async -> MeierScriptRunner.Result {
        guard var command = mode == .syntaxCheck ? syntaxCheck : run else {
            return MeierScriptRunner.Result(standardOutput: "", standardError: "", exitCode: 0, timedOut: false,
                                            wasCancelled: false, duration: 0, outputTruncated: false)
        }
        if languageID == "javascript", Self.looksLikeESModule(source) {
            command.arguments.insert("--input-type=module", at: 0)
        }
        var temporaryFolder: URL?
        var fileURL: URL?
        if case .temporaryFile(let fileExtension) = command.input {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("NeonVisionEditor-Run-\(UUID().uuidString)", isDirectory: true)
            let file = folder.appendingPathComponent("\(Self.temporaryFileStem).\(fileExtension)")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try Data(source.utf8).write(to: file, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: folder)
                return MeierScriptRunner.Result(standardOutput: "", standardError: error.localizedDescription,
                                                exitCode: -1, timedOut: false, wasCancelled: false, duration: 0,
                                                outputTruncated: false)
            }
            temporaryFolder = folder
            fileURL = file
        }
        defer { if let temporaryFolder { try? FileManager.default.removeItem(at: temporaryFolder) } }
        var environment = Self.childEnvironment()
        if environment["SDKROOT"] == nil, let sdk = Self.sdkRoot(forToolAt: executableURL) {
            environment["SDKROOT"] = sdk
        }
        var result = await MeierScriptRunner.runProcess(
            executableURL: executableURL,
            arguments: Self.arguments(for: command, fileURL: fileURL),
            input: command.input == .standardInput ? source : "",
            environment: environment,
            workingDirectory: workingDirectory,
            timeout: timeout)
        if let fileURL {
            // Messages name the temporary file; show the plain file name instead.
            let name = fileURL.lastPathComponent
            let paths = Set([fileURL.path, fileURL.resolvingSymlinksInPath().path]).sorted { $0.count > $1.count }
            for path in paths {
                result.standardOutput = result.standardOutput.replacingOccurrences(of: path, with: name)
                result.standardError = result.standardError.replacingOccurrences(of: path, with: name)
            }
        }
        return result
    }

    /// The first syntax error with its line, read from the checker's output.
    func firstDiagnostic(in output: String) -> MeierScriptLanguage.Diagnostic? {
        guard let diagnosticLinePattern,
              let regex = try? NSRegularExpression(pattern: diagnosticLinePattern) else { return nil }
        let nsOutput = output as NSString
        guard let match = regex.firstMatch(in: output, range: NSRange(location: 0, length: nsOutput.length)),
              let line = Int(nsOutput.substring(with: match.range(at: 1))), line > 0 else { return nil }
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let message = lines.last { $0.localizedCaseInsensitiveContains("error") } ?? lines.first ?? ""
        return MeierScriptLanguage.Diagnostic(line: line, column: 1, message: message)
    }
}
#endif

import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
final class ScriptInterpreterTests: XCTestCase {
    func testLanguagesMapToInterpreters() {
        XCTAssertEqual(ScriptInterpreter.forLanguage("Python")?.displayName, "Python")
        XCTAssertEqual(ScriptInterpreter.forLanguage("javascript")?.run.executableNames, ["node"])
        XCTAssertEqual(ScriptInterpreter.forLanguage("lua")?.syntaxCheck?.executableNames, ["luac"])
        XCTAssertNil(ScriptInterpreter.forLanguage("powershell")?.syntaxCheck)
        XCTAssertNil(ScriptInterpreter.forLanguage("perl")?.syntaxCheck, "perl -c runs BEGIN blocks")
        for id in ["plain", "markdown", "json", "meierscript", "typescript", "c"] {
            XCTAssertNil(ScriptInterpreter.forLanguage(id), id)
        }
        XCTAssertEqual(Set(ScriptInterpreter.all.map(\.languageID)).count, ScriptInterpreter.all.count)
    }

    func testDeveloperToolShimsInUsrBinAreSkipped() {
        let installed: Set<String> = ["/usr/bin/swift", "/usr/bin/ruby",
                                      "/Library/Developer/CommandLineTools/usr/bin/swift"]
        let directories = ScriptInterpreter.searchDirectories(inheritedPath: "/usr/bin:/bin")
        XCTAssertEqual(Array(directories.prefix(2)), ScriptInterpreter.preferredSearchDirectories)
        XCTAssertEqual(directories.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertEqual(ScriptInterpreter.locate("swift", directories: directories) { installed.contains($0) }?.path,
                       "/Library/Developer/CommandLineTools/usr/bin/swift")
        XCTAssertEqual(ScriptInterpreter.locate("ruby", directories: directories) { installed.contains($0) }?.path,
                       "/usr/bin/ruby")
        XCTAssertNil(ScriptInterpreter.locate("python3", directories: ["/usr/bin"]) { _ in true })
    }

    func testChildPathPutsHomebrewFirstWithoutDuplicates() {
        let environment = ScriptInterpreter.childEnvironment(["PATH": "/usr/bin:/opt/homebrew/bin", "HOME": "/h"])
        XCTAssertEqual(environment["PATH"], "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        XCTAssertEqual(environment["HOME"], "/h")
    }

    func testSDKRootIsFoundNextToTheDeveloperTool() {
        let xcode = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift")
        XCTAssertEqual(ScriptInterpreter.sdkRoot(forToolAt: xcode) { _ in true },
                       "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")
        let tools = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/swift")
        XCTAssertEqual(ScriptInterpreter.sdkRoot(forToolAt: tools) { _ in true },
                       "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")
        XCTAssertNil(ScriptInterpreter.sdkRoot(forToolAt: URL(fileURLWithPath: "/opt/homebrew/bin/node")) { _ in true })
        XCTAssertNil(ScriptInterpreter.sdkRoot(forToolAt: tools) { _ in false })
    }

    func testESModuleDetection() {
        XCTAssertTrue(ScriptInterpreter.looksLikeESModule("import fs from 'node:fs'\n"))
        XCTAssertTrue(ScriptInterpreter.looksLikeESModule("// x\nexport const a = 1\n"))
        XCTAssertTrue(ScriptInterpreter.looksLikeESModule("import { a } from './a.js'"))
        XCTAssertTrue(ScriptInterpreter.looksLikeESModule("import './side-effect.js'"))
        XCTAssertFalse(ScriptInterpreter.looksLikeESModule("const m = await import('x')\n"))
        XCTAssertFalse(ScriptInterpreter.looksLikeESModule("import('x').then(f)\n"))
        XCTAssertFalse(ScriptInterpreter.looksLikeESModule("const fs = require('fs')\nmodule.exports = {}\n"))
    }

    func testFilePlaceholderIsReplaced() throws {
        let swift = try XCTUnwrap(ScriptInterpreter.forLanguage("swift"))
        let file = URL(fileURLWithPath: "/tmp/x/script.swift")
        XCTAssertEqual(ScriptInterpreter.arguments(for: try XCTUnwrap(swift.syntaxCheck), fileURL: file),
                       ["-parse", "/tmp/x/script.swift"])
    }

    /// Sample messages as the tools print them (checked on macOS 27).
    func testFirstDiagnosticReadsTheErrorLine() {
        let samples: [(String, String, Int)] = [
            ("python", "  File \"<stdin>\", line 2\n    if x\n        ^\nSyntaxError: expected ':'\n", 2),
            ("javascript", "[stdin]:3\nlet = ;\n    ^\n\nSyntaxError: Unexpected token '='\n", 3),
            ("ruby", "-:2: syntax error, unexpected end-of-input, expecting ')'\n", 2),
            ("ruby", "/opt/homebrew/bin/ruby: -:3: syntax error found (SyntaxError)\n", 3),
            ("bash", "script.sh: line 4: syntax error near unexpected token `then'\n", 4),
            ("zsh", "script.zsh:3: parse error near `\\n'\n", 3),
            ("r", "Error in parse(file(\"stdin\")) : 2:6: unexpected ')'\n", 2),
            ("swift", "script.swift:2:5: error: expected pattern\n", 2),
            ("php", "PHP Parse error:  syntax error, unexpected end of file in Standard input code on line 5\n", 5),
            ("lua", "luac: stdin:7: unexpected symbol near 'end'\n", 7),
        ]
        for (language, output, line) in samples {
            let diagnostic = ScriptInterpreter.forLanguage(language)?.firstDiagnostic(in: output)
            XCTAssertEqual(diagnostic?.line, line, language)
            XCTAssertFalse(diagnostic?.message.isEmpty ?? true, language)
        }
        XCTAssertNil(ScriptInterpreter.forLanguage("python")?.firstDiagnostic(in: "Traceback: boom"))
    }

    /// Runs every interpreter installed on this Mac inside the app's sandbox:
    /// separate streams, a check that does not execute, and a failing check.
    func testInstalledInterpretersRunAndCheck() async throws {
        let cases: [(id: String, ok: String, bad: String, badLine: Int?)] = [
            ("python", "import sys\nprint('out')\nprint('err', file=sys.stderr)\n", "x = 1\nif x\n", 2),
            ("javascript", "console.log('out')\nconsole.error('err')\n", "console.log(1)\nconst a = ;\n", 2),
            ("ruby", "puts 'out'\n$stderr.puts 'err'\n", "x = 1\nputs(1\n", 2),
            ("perl", "print \"out\\n\";\nprint STDERR \"err\\n\";\n", "", nil),
            ("javascript", "import { stderr } from 'node:process'\nconsole.log('out')\nstderr.write('err\\n')\n",
             "import fs from 'node:fs'\nconst a = ;\n", 2),
            ("bash", "echo out\necho err >&2\n", "echo ok\nif then\n", 2),
            ("zsh", "echo out\necho err >&2\n", "echo ok\nif then\n", nil),
            ("r", "cat('out\\n')\nmessage('err')\n", "x <- 1\ny <- )\n", 2),
            ("swift", "import Foundation\nprint(\"out\")\nFileHandle.standardError.write(\"err\\n\".data(using: .utf8)!)\n",
             "let a = 1\nlet = 2\n", 2),
        ]
        var ranAny = false
        for item in cases {
            let interpreter = try XCTUnwrap(ScriptInterpreter.forLanguage(item.id))
            guard let runTool = interpreter.locate(interpreter.run, workingDirectory: nil) else { continue }
            ranAny = true
            let run = await interpreter.execute(source: item.ok, mode: .run, executableURL: runTool,
                                                workingDirectory: nil, timeout: 60)
            XCTAssertEqual(run.exitCode, 0, "\(item.id): \(run.standardError)")
            XCTAssertEqual(run.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines), "out", item.id)
            XCTAssertTrue(run.standardError.contains("err"), "\(item.id): \(run.standardError)")

            guard let check = interpreter.syntaxCheck,
                  let checkTool = interpreter.locate(check, workingDirectory: nil) else { continue }
            let valid = await interpreter.execute(source: item.ok, mode: .syntaxCheck, executableURL: checkTool,
                                                  workingDirectory: nil, timeout: 60)
            XCTAssertEqual(valid.exitCode, 0, "\(item.id): \(valid.standardError)")
            XCTAssertFalse(valid.standardOutput.contains("out\n"), "\(item.id) check must not run")
            let invalid = await interpreter.execute(source: item.bad, mode: .syntaxCheck, executableURL: checkTool,
                                                    workingDirectory: nil, timeout: 60)
            XCTAssertNotEqual(invalid.exitCode, 0, item.id)
            XCTAssertFalse(invalid.standardError.contains("NeonVisionEditor-Run-"), "\(item.id) leaks the temporary path")
            let line = interpreter.firstDiagnostic(in: invalid.standardError)?.line
            if let badLine = item.badLine {
                XCTAssertEqual(line, badLine, "\(item.id): \(invalid.standardError)")
            } else {
                XCTAssertNotNil(line, "\(item.id): \(invalid.standardError)")
            }
        }
        if !ranAny { throw XCTSkip("No script interpreter installed") }
    }

    /// A script that exits without reading a large stdin must not kill the
    /// app with SIGPIPE.
    func testLargeInputToAToolThatIgnoresStdinDoesNotRaiseSIGPIPE() async {
        let source = String(repeating: "x", count: 4 * 1024 * 1024)
        let result = await MeierScriptRunner.runProcess(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                                                        arguments: [], input: source, environment: nil,
                                                        workingDirectory: nil, timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
    }
}
#endif

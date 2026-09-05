import Foundation
import XCTest
@testable import Neon_Vision_Editor

final class EditorAgentCoreTests: XCTestCase {
    func testWorkspaceExcludesSecretFilesAndCredentialContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = root.appendingPathComponent(".env")
        let source = root.appendingPathComponent("config.swift")
        try "PRIVATE=needle".write(to: environment, atomically: true, encoding: .utf8)
        try "api_key = 'secret-needle-1234567890'".write(to: source, atomically: true, encoding: .utf8)
        let workspace = EditorAgentWorkspace(rootURL: root, allowedFileURLs: [environment, source])
        await XCTAssertThrowsErrorAsync { _ = try await workspace.readFile(relativePath: ".env") }
        await XCTAssertThrowsErrorAsync { _ = try await workspace.readFile(relativePath: "config.swift") }
        let matches = try await workspace.searchProject(query: "needle")
        XCTAssertTrue(matches.isEmpty)
    }
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorAgentCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
    }

    func testWorkspaceRejectsPathsOutsideCapturedProject() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "let greeting = \"Hello\"\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let workspace = EditorAgentWorkspace(
            rootURL: temporaryDirectoryURL,
            allowedFileURLs: [sourceURL]
        )

        let content = try await workspace.readFile(relativePath: "Sources/App.swift", maximumCharacters: 200)
        XCTAssertTrue(content.contains("greeting"))

        await XCTAssertThrowsErrorAsync {
            _ = try await workspace.readFile(relativePath: "../Secrets.txt", maximumCharacters: 200)
        }
        await XCTAssertThrowsErrorAsync {
            _ = try await workspace.readFile(relativePath: "/etc/passwd", maximumCharacters: 200)
        }
    }

    func testWorkspaceSearchIsBoundedAndRecordsActivity() async throws {
        let firstURL = temporaryDirectoryURL.appendingPathComponent("First.swift")
        let secondURL = temporaryDirectoryURL.appendingPathComponent("Second.swift")
        try "struct First { let needle = 1 }\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "struct Second { let needle = 2 }\n".write(to: secondURL, atomically: true, encoding: .utf8)
        let workspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [firstURL, secondURL])

        let results = try await workspace.searchProject(query: "needle", maximumResults: 1)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].snippet.contains("needle"))
        let activity = await workspace.activitySnapshot()
        XCTAssertEqual(activity.last?.kind, .search)
        XCTAssertEqual(activity.last?.status, .succeeded)
    }

    func testEditProposalRejectsChangedSelection() {
        let tabID = UUID()
        let proposal = EditorAgentEditProposal(
            tabID: tabID,
            range: NSRange(location: 4, length: 3),
            source: "old",
            replacement: "new",
            summary: "Update the value"
        )

        XCTAssertTrue(proposal.matches(tabID: tabID, range: proposal.range, currentSource: "old"))
        XCTAssertFalse(proposal.matches(tabID: tabID, range: proposal.range, currentSource: "changed"))
        XCTAssertFalse(proposal.matches(tabID: UUID(), range: proposal.range, currentSource: "old"))
    }

    func testEditPromptIncludesExactSelectionAndPreservesReplacementWhitespace() throws {
        let source = "    print(\"before\")\n\n"
        let target = EditorAgentEditTarget(tabID: UUID(), range: NSRange(location: 20, length: source.utf16.count), source: source)
        let prompt = try EditorAgentPromptPolicy.prompt("USER: change the message", mode: .edit, target: target)
        XCTAssertTrue(prompt.hasPrefix("USER: change the message"))
        let encodedSource = try XCTUnwrap(prompt.components(separatedBy: "source; replace this entire selection only):\n").last)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data(encodedSource.utf8)), source)
        let replacement = "    print(\"after\")\n\n"
        let proposal = EditorAgentPromptPolicy.editProposal(target: target, replacement: replacement, summary: "Changed message", mode: .edit)
        XCTAssertEqual(proposal?.replacement, replacement)
        XCTAssertEqual(proposal?.source, source)
    }

    func testEditPromptRejectsMissingOrOversizedSelectionAndExcessContext() {
        XCTAssertThrowsError(try EditorAgentPromptPolicy.prompt("change it", mode: .edit, target: nil))
        let source = String(repeating: "x", count: 32_001)
        let target = EditorAgentEditTarget(tabID: UUID(), range: NSRange(location: 0, length: source.count), source: source)
        XCTAssertThrowsError(try EditorAgentPromptPolicy.prompt("change it", mode: .edit, target: target))
        XCTAssertNoThrow(try EditorAgentPromptPolicy.validateBudget(inputTokens: 2_000, contextSize: 4_096, reservedTokens: 2_096))
        XCTAssertThrowsError(try EditorAgentPromptPolicy.validateBudget(inputTokens: 2_001, contextSize: 4_096, reservedTokens: 2_096))
    }

    func testWorkspaceRejectsFileReplacedWithSymlinkDuringSearchAndRead() async throws {
        let source = temporaryDirectoryURL.appendingPathComponent("Source.swift")
        let secret = temporaryDirectoryURL.appendingPathComponent("Secret.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try "needle private".write(to: secret, atomically: true, encoding: .utf8)
        let workspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [source])
        try FileManager.default.removeItem(at: source)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: secret)
        await XCTAssertThrowsErrorAsync { _ = try await workspace.readFile(relativePath: "Source.swift") }
        let results = try await workspace.searchProject(query: "needle")
        XCTAssertTrue(results.isEmpty)
    }

    func testWorkspaceRejectsAncestorSymlinkAndNonregularFiles() async throws {
        let directory = temporaryDirectoryURL.appendingPathComponent("Sources")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Source.swift")
        try "needle".write(to: source, atomically: true, encoding: .utf8)
        let workspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [source])
        let movedDirectory = temporaryDirectoryURL.appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: directory, to: movedDirectory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: movedDirectory)
        await XCTAssertThrowsErrorAsync { _ = try await workspace.readFile(relativePath: "Sources/Source.swift") }
        let results = try await workspace.searchProject(query: "needle")
        XCTAssertTrue(results.isEmpty)

        let specialFile = temporaryDirectoryURL.appendingPathComponent("Directory.swift")
        try FileManager.default.createDirectory(at: specialFile, withIntermediateDirectories: true)
        let specialWorkspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [specialFile])
        await XCTAssertThrowsErrorAsync { _ = try await specialWorkspace.readFile(relativePath: "Directory.swift") }
    }

    func testWorkspaceEnforcesRunToolBudgetAndCancellation() async throws {
        let source = temporaryDirectoryURL.appendingPathComponent("Source.swift")
        try "needle".write(to: source, atomically: true, encoding: .utf8)
        let workspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [source])
        for _ in 0..<12 { _ = try await workspace.readFile(relativePath: "Source.swift") }
        await XCTAssertThrowsErrorAsync { _ = try await workspace.searchProject(query: "needle") }

        let freshWorkspace = EditorAgentWorkspace(rootURL: temporaryDirectoryURL, allowedFileURLs: [source])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await freshWorkspace.readFile(relativePath: "Source.swift")
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled tool read must fail")
        } catch is CancellationError {
            // Cancellation must be preserved rather than treated as an empty result.
        }
    }

    func testVerificationResolverProducesArgumentOnlyPlans() throws {
        let packageURL = temporaryDirectoryURL.appendingPathComponent("Package.swift")
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("Sources/App.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// package\n".write(to: packageURL, atomically: true, encoding: .utf8)
        try "print(\"ok\")\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let syntax = EditorAgentVerificationResolver.plan(
            for: .syntax,
            rootURL: temporaryDirectoryURL,
            selectedFileURL: sourceURL
        )
        XCTAssertEqual(syntax?.executableURL.path, "/usr/bin/xcrun")
        XCTAssertEqual(syntax?.arguments.prefix(2), ["swiftc", "-parse"])
        XCTAssertFalse(syntax?.arguments.joined(separator: " ").contains(";") == true)

        let tests = EditorAgentVerificationResolver.plan(
            for: .tests,
            rootURL: temporaryDirectoryURL,
            selectedFileURL: sourceURL
        )
        XCTAssertEqual(tests?.executableURL.path, "/usr/bin/swift")
        XCTAssertEqual(tests?.arguments, ["test"])

        let unsafe = EditorAgentVerificationPlan(
            action: .tests,
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "rm -rf /"],
            workingDirectoryURL: temporaryDirectoryURL
        )
        XCTAssertFalse(EditorAgentVerificationRunner.isAllowed(unsafe))
        XCTAssertTrue(syntax.map(EditorAgentVerificationRunner.isAllowed) == true)
    }

    func testVerificationRunnerHonorsSandboxExecutionBoundary() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("Check.swift")
        try "let value = 42\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        let plan = try XCTUnwrap(EditorAgentVerificationResolver.plan(
            for: .syntax,
            rootURL: temporaryDirectoryURL,
            selectedFileURL: sourceURL
        ))

        let result = await EditorAgentVerificationRunner.run(plan, timeout: 30)

        if EditorAgentVerificationRunner.executionIsSupported {
            XCTAssertTrue(result.succeeded, result.output)
            XCTAssertEqual(result.terminationStatus, 0)
        } else {
            XCTAssertFalse(result.succeeded)
            XCTAssertEqual(result.terminationStatus, -1)
            XCTAssertTrue(result.output.contains("App Store sandbox"))
        }
    }

    func testVerificationRunnerRejectsExtraXcodebuildArguments() throws {
        let projectURL = temporaryDirectoryURL.appendingPathComponent("Sample.xcodeproj")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let plan = EditorAgentVerificationPlan(
            action: .build,
            executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
            arguments: [
                "-project", projectURL.path,
                "-scheme", "Sample",
                "-destination", "platform=macOS",
                "-derivedDataPath", "/tmp/Unexpected",
                "build"
            ],
            workingDirectoryURL: temporaryDirectoryURL
        )

        XCTAssertFalse(EditorAgentVerificationRunner.isAllowed(plan))
    }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            // Expected.
        }
    }
}

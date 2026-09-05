import Foundation
import XCTest
@testable import Neon_Vision_Editor

final class EditorAgentCoreTests: XCTestCase {
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

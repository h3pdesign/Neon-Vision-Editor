import XCTest
@testable import Neon_Vision_Editor

#if os(macOS)
final class GitServiceTests: XCTestCase {
    private var repositoryURL: URL!

    override func setUpWithError() throws {
        repositoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: repositoryURL, withIntermediateDirectories: true)
        try runGit(["init"])
        try runGit(["config", "user.name", "Neon Vision Editor Tests"])
        try runGit(["config", "user.email", "tests@example.invalid"])
    }

    override func tearDownWithError() throws {
        if let repositoryURL {
            try? FileManager.default.removeItem(at: repositoryURL)
        }
        repositoryURL = nil
    }

    func testCommitDiffUsesAlreadyLoadedDetail() async throws {
        let document = repositoryURL.appendingPathComponent("notes.md")
        try "first\n".write(to: document, atomically: true, encoding: .utf8)
        try runGit(["add", "notes.md"])
        try runGit(["commit", "-m", "Initial notes"])
        try "second\n".write(to: document, atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "Update notes"])

        let service = try XCTUnwrap(GitService(projectURL: repositoryURL))
        let history = await service.historyGraph(count: 1)
        let hash = try await MainActor.run { try XCTUnwrap(history.first?.hash) }
        let detail = try await service.commitDetail(hash: hash)
        let diff = try await service.commitDiff(detail: detail)
        let result = await MainActor.run {
            (title: diff.title, leftContent: diff.leftContent, rightContent: diff.rightContent, shortHash: detail.shortHash)
        }

        XCTAssertEqual(result.title, "Commit \(result.shortHash)")
        XCTAssertTrue(result.leftContent.contains("first"))
        XCTAssertTrue(result.rightContent.contains("second"))
    }

    private func runGit(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/Library/Developer/CommandLineTools/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = repositoryURL
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed: \(error)")
    }
}
#endif

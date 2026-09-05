import Foundation
import XCTest
@testable import Neon_Vision_Editor

final class EditorAgentVerificationRunnerTests: XCTestCase {
    private func withScript(
        _ source: String,
        body: (EditorAgentVerificationPlan, URL) async throws -> Void
    ) async throws {
        guard EditorAgentVerificationRunner.executionIsSupported else {
            throw XCTSkip("Requires the unsandboxed direct macOS test host.")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("verification.py")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let plan = try XCTUnwrap(EditorAgentVerificationResolver.plan(
            for: .runSelectedFile, rootURL: root, selectedFileURL: file
        ))
        try await body(plan, root)
    }

    func testTimeoutReturnsWhenProgramIgnoresSIGTERM() async throws {
        try await withScript("import signal, time\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\ntime.sleep(60)\n") { plan, _ in
            let clock = ContinuousClock()
            let start = clock.now
            let result = await EditorAgentVerificationRunner.run(plan, timeout: 1)
            XCTAssertTrue(result.didTimeOut)
            XCTAssertFalse(result.succeeded)
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(5))
        }
    }

    func testOutputRetentionIsBoundedAndKeepsTail() async throws {
        try await withScript("import sys\nsys.stdout.write('x' * (2 * 1024 * 1024))\nsys.stdout.write('TAIL_MARKER')\n") { plan, _ in
            let result = await EditorAgentVerificationRunner.run(plan)
            XCTAssertTrue(result.succeeded)
            XCTAssertTrue(result.output.hasSuffix("TAIL_MARKER"))
            XCTAssertTrue(result.output.contains("Earlier output was truncated"))
            XCTAssertLessThan(result.output.utf8.count, 129 * 1024)
        }
    }

    func testTimeoutStopsOrdinaryChildProcesses() async throws {
        let source = """
        import subprocess, sys, time
        subprocess.Popen([sys.executable, '-c', "import time; from pathlib import Path; time.sleep(2); Path('child-survived').touch()"])
        print('CHILD_STARTED', flush=True)
        time.sleep(60)
        """
        try await withScript(source) { plan, root in
            let result = await EditorAgentVerificationRunner.run(plan, timeout: 1)
            XCTAssertTrue(result.didTimeOut)
            XCTAssertTrue(result.output.contains("CHILD_STARTED"))
            try await Task.sleep(for: .seconds(2))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("child-survived").path))
        }
    }

    func testAlreadyCancelledTaskDoesNotLaunchProgram() async throws {
        try await withScript("from pathlib import Path\nPath('launched').touch()\n") { plan, root in
            let result = await Task {
                withUnsafeCurrentTask { $0?.cancel() }
                return await EditorAgentVerificationRunner.run(plan)
            }.value
            XCTAssertTrue(result.wasCancelled)
            XCTAssertFalse(result.succeeded)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("launched").path))
        }
    }
}

#if os(macOS)
import AppKit
import Foundation

/// Runs scripts with the `meierscript` CLI that SidUI Editor and SidUI Viewer
/// ship in `Contents/SharedSupport`. Nothing is bundled or downloaded: the
/// runner only uses an installed, code-signed host app.
nonisolated enum MeierScriptRunner {
    static let hostBundleIdentifiers = ["de.sidneydevelopment.SidUI-Editor", "de.sidneydevelopment.SidUI-Viewer"]
    static let cliRelativePath = "Contents/SharedSupport/meierscript"
    static let knownHostAppPaths = [
        "/Applications/SidUI Editor.app",
        "/Library/Application Support/Sidney Development/SidUI Viewer.app",
        "/Applications/SidUI Viewer.app"
    ]
    /// Caps each captured stream so runaway `print` loops cannot exhaust memory.
    static let maximumCapturedBytes = 512 * 1024

    struct Result: Equatable, Sendable {
        var standardOutput: String
        var standardError: String
        var exitCode: Int32
        var timedOut: Bool
        var wasCancelled: Bool
        var duration: TimeInterval
        var outputTruncated: Bool
    }

    enum Mode: Sendable {
        case run
        case syntaxCheck
    }

    /// Host app candidates in preference order: registered apps first, then
    /// the default install locations. Pure so it can be tested without disk.
    static func candidateHostApps(registered: [URL]) -> [URL] {
        var seen = Set<String>()
        return (registered + knownHostAppPaths.map { URL(fileURLWithPath: $0, isDirectory: true) })
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    static func locateCLI(fileManager: FileManager = .default) -> URL? {
        let registered = hostBundleIdentifiers.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        return candidateHostApps(registered: registered)
            .map { $0.appendingPathComponent(cliRelativePath, isDirectory: false) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    /// Feeds the script through stdin (`meierscript -`), so unsaved edits run
    /// without temporary files. stdout and stderr are captured separately.
    static func execute(
        source: String,
        mode: Mode,
        cliURL: URL,
        workingDirectory: URL?,
        timeout: TimeInterval
    ) async -> Result {
        let input = mode == .syntaxCheck ? MeierScriptLanguage.syntaxCheckSource(for: source) : source
        let process = Process()
        process.executableURL = cliURL
        process.arguments = ["-"]
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let start = Date()
        let stdoutCollector = PipeCollector(limit: maximumCapturedBytes)
        let stderrCollector = PipeCollector(limit: maximumCapturedBytes)
        stdoutCollector.attach(to: stdoutPipe.fileHandleForReading)
        stderrCollector.attach(to: stderrPipe.fileHandleForReading)

        let exit = ProcessExitSignal()
        let control = ProcessControl(process)
        process.terminationHandler = { exit.signal(status: $0.terminationStatus) }
        do {
            try process.run()
        } catch {
            stdoutCollector.detach()
            stderrCollector.detach()
            return Result(standardOutput: "", standardError: error.localizedDescription, exitCode: -1,
                          timedOut: false, wasCancelled: false, duration: 0, outputTruncated: false)
        }
        let writer = stdinPipe.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async {
            try? writer.write(contentsOf: Data(input.utf8))
            try? writer.close()
        }

        var timedOut = false
        var cancelled = false
        let status: Int32 = await withTaskCancellationHandler {
            await withTaskGroup(of: Int32?.self) { group in
                group.addTask { await exit.wait() }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(max(0.1, timeout) * 1_000_000_000))
                    return nil
                }
                var finished: Int32?
                if let first = await group.next() { finished = first }
                if finished == nil {
                    timedOut = !Task.isCancelled
                    cancelled = Task.isCancelled
                    control.stop()
                    finished = await exit.wait()
                }
                group.cancelAll()
                return finished ?? -1
            }
        } onCancel: {
            control.stop()
        }
        if Task.isCancelled { cancelled = true; timedOut = false }

        let output = stdoutCollector.finish()
        let error = stderrCollector.finish()
        var standardError = String(decoding: error.data, as: UTF8.self)
        if mode == .syntaxCheck {
            standardError = MeierScriptLanguage.remapSyntaxCheckDiagnostics(standardError)
        }
        return Result(
            standardOutput: String(decoding: output.data, as: UTF8.self),
            standardError: standardError,
            exitCode: status,
            timedOut: timedOut,
            wasCancelled: cancelled,
            duration: Date().timeIntervalSince(start),
            outputTruncated: output.truncated || error.truncated
        )
    }

    /// Lets the cancellation handler stop the child; SIGKILL follows if the
    /// script ignores SIGTERM.
    private final class ProcessControl: @unchecked Sendable {
        private let process: Process
        init(_ process: Process) { self.process = process }
        func stop() {
            guard process.isRunning else { return }
            process.terminate()
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [self] in
                if self.process.isRunning { kill(pid, SIGKILL) }
            }
        }
    }

    private final class PipeCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let limit: Int
        private var data = Data()
        private var truncated = false
        private var handle: FileHandle?
        private let drained = DispatchSemaphore(value: 0)

        init(limit: Int) { self.limit = limit }

        func attach(to handle: FileHandle) {
            self.handle = handle
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    self.drained.signal()
                    return
                }
                self.lock.lock()
                let room = max(0, self.limit - self.data.count)
                if chunk.count > room { self.truncated = true }
                if room > 0 { self.data.append(chunk.prefix(room)) }
                self.lock.unlock()
            }
        }

        func detach() {
            handle?.readabilityHandler = nil
        }

        /// Waits briefly for EOF so the last chunk written before exit is kept.
        func finish() -> (data: Data, truncated: Bool) {
            _ = drained.wait(timeout: .now() + 1)
            detach()
            lock.lock(); defer { lock.unlock() }
            return (data, truncated)
        }
    }

    private final class ProcessExitSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var status: Int32?
        private var waiters: [CheckedContinuation<Int32, Never>] = []

        func signal(status: Int32) {
            lock.lock()
            self.status = status
            let pending = waiters
            waiters.removeAll()
            lock.unlock()
            pending.forEach { $0.resume(returning: status) }
        }

        func wait() async -> Int32 {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let status {
                    lock.unlock()
                    continuation.resume(returning: status)
                } else {
                    waiters.append(continuation)
                    lock.unlock()
                }
            }
        }
    }
}
#endif

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
        var result = await runProcess(executableURL: cliURL, arguments: ["-"], input: input,
                                      environment: nil, workingDirectory: workingDirectory, timeout: timeout)
        result.standardError = MeierScriptLanguage.remapDiagnostics(
            result.standardError, source: source, preludeLineCount: mode == .syntaxCheck ? 1 : 0)
        return result
    }

    /// Runs one tool with `input` on stdin, capturing stdout and stderr
    /// separately. Shared by the MeierScript CLI and the script interpreters
    /// of the run console (`ScriptInterpreter`). `environment` nil inherits.
    static func runProcess(
        executableURL: URL,
        arguments: [String],
        input: String,
        environment: [String: String]?,
        workingDirectory: URL?,
        timeout: TimeInterval
    ) async -> Result {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
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
        // A tool that exits before reading all of stdin would otherwise raise
        // SIGPIPE in the app; with this flag the write fails with EPIPE instead.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        DispatchQueue.global(qos: .userInitiated).async {
            if !input.isEmpty { try? writer.write(contentsOf: Data(input.utf8)) }
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

        let output = await stdoutCollector.finish()
        let error = await stderrCollector.finish()
        return Result(
            standardOutput: String(decoding: output.data, as: UTF8.self),
            standardError: String(decoding: error.data, as: UTF8.self),
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
        private let drained = AsyncLatch()

        init(limit: Int) { self.limit = limit }

        func attach(to handle: FileHandle) {
            self.handle = handle
            handle.readabilityHandler = { [weak self] handle in
                let chunk = handle.availableData
                guard let self else { return }
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    self.drained.open()
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
        /// Suspends instead of blocking a thread: the readability handler runs
        /// at a lower QoS, and a blocking wait would invert priorities.
        func finish() async -> (data: Data, truncated: Bool) {
            await drained.wait(timeoutNanoseconds: 1_000_000_000)
            detach()
            return lock.withLock { (data, truncated) }
        }
    }

    /// One-shot signal that can be awaited with a timeout and cancellation.
    private final class AsyncLatch: @unchecked Sendable {
        private let lock = NSLock()
        private var isOpen = false
        private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

        func open() {
            lock.lock()
            isOpen = true
            let pending = Array(waiters.values)
            waiters.removeAll()
            lock.unlock()
            pending.forEach { $0.resume() }
        }

        func wait() async {
            let id = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    if isOpen || Task.isCancelled {
                        lock.unlock()
                        continuation.resume()
                    } else {
                        waiters[id] = continuation
                        lock.unlock()
                    }
                }
            } onCancel: {
                lock.lock()
                let continuation = waiters.removeValue(forKey: id)
                lock.unlock()
                continuation?.resume()
            }
        }

        func wait(timeoutNanoseconds: UInt64) async {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.wait() }
                group.addTask { try? await Task.sleep(nanoseconds: timeoutNanoseconds) }
                await group.next()
                group.cancelAll()
            }
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

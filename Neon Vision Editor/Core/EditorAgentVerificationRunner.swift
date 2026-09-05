import Foundation
#if os(macOS)
import Security
import Darwin
#endif

nonisolated struct EditorAgentVerificationResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let plan: EditorAgentVerificationPlan
    let terminationStatus: Int32
    let output: String
    let didTimeOut: Bool
    var wasCancelled: Bool = false

    var succeeded: Bool {
        terminationStatus == 0 && !didTimeOut && !wasCancelled
    }
}

nonisolated enum EditorAgentVerificationRunner {
    private static let allowedExecutables: Set<String> = [
        "/usr/bin/xcrun",
        "/usr/bin/xcodebuild",
        "/usr/bin/swift",
        "/usr/bin/python3"
    ]
    private static let maximumOutputBytes = 128 * 1024

    static var executionIsSupported: Bool {
#if os(macOS) && !APP_STORE_BUILD
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.app-sandbox" as CFString,
                nil
              ) else { return true }
        return (value as? Bool) != true
#else
        false
#endif
    }

    static func isAllowed(_ plan: EditorAgentVerificationPlan) -> Bool {
        guard allowedExecutables.contains(plan.executableURL.path),
              plan.workingDirectoryURL.isFileURL,
              !plan.arguments.isEmpty else { return false }
        switch plan.action {
        case .none:
            return false
        case .syntax:
            return plan.executableURL.path == "/usr/bin/xcrun" &&
                plan.arguments.count == 3 &&
                plan.arguments.prefix(2) == ["swiftc", "-parse"] &&
                isContainedFile(plan.arguments[2], by: plan.workingDirectoryURL)
        case .runSelectedFile:
            if plan.executableURL.path == "/usr/bin/xcrun" {
                return plan.arguments.count == 2 &&
                    plan.arguments[0] == "swift" &&
                    isContainedFile(plan.arguments[1], by: plan.workingDirectoryURL)
            }
            return plan.executableURL.path == "/usr/bin/python3" &&
                plan.arguments.count == 1 &&
                isContainedFile(plan.arguments[0], by: plan.workingDirectoryURL)
        case .build, .tests:
            if plan.executableURL.path == "/usr/bin/swift" {
                return plan.arguments == [plan.action == .build ? "build" : "test"]
            }
            let finalAction = plan.action == .build ? "build" : "test"
            return plan.executableURL.path == "/usr/bin/xcodebuild" &&
                plan.arguments.count == 7 &&
                plan.arguments[0] == "-project" &&
                plan.arguments[1].hasSuffix(".xcodeproj") &&
                isContainedFile(plan.arguments[1], by: plan.workingDirectoryURL) &&
                plan.arguments[2] == "-scheme" &&
                !plan.arguments[3].isEmpty &&
                plan.arguments[4] == "-destination" &&
                plan.arguments[5] == "platform=macOS" &&
                plan.arguments[6] == finalAction
        }
    }

    private static func isContainedFile(_ path: String, by rootURL: URL) -> Bool {
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    static func run(
        _ plan: EditorAgentVerificationPlan,
        timeout: TimeInterval = 120
    ) async -> EditorAgentVerificationResult {
#if !os(macOS) || APP_STORE_BUILD
        return .init(
            plan: plan,
            terminationStatus: -1,
            output: "Local verification is unavailable in the App Store sandbox. Use the direct macOS build or run the displayed command yourself.",
            didTimeOut: false
        )
#else
        guard #available(macOS 27.0, *) else {
            return .init(plan: plan, terminationStatus: -1, output: "Agent verification requires macOS 27 or later.", didTimeOut: false)
        }
        guard executionIsSupported else {
            return .init(
                plan: plan,
                terminationStatus: -1,
                output: "Local verification is unavailable in the App Store sandbox. Use the direct macOS build or run the displayed command yourself.",
                didTimeOut: false
            )
        }
        guard isAllowed(plan) else {
            return .init(
                plan: plan,
                terminationStatus: -1,
                output: "Verification was blocked because the executable or arguments were not allowlisted.",
                didTimeOut: false
            )
        }

        guard !Task.isCancelled else {
            return .init(plan: plan, terminationStatus: -1, output: "Verification cancelled before launch.", didTimeOut: false, wasCancelled: true)
        }
        let verificationTask: Task<EditorAgentVerificationResult, Never> = Task.detached(priority: .userInitiated) {
            do {
                try Task.checkCancellation()
                let pipe = Pipe()
                defer {
                    try? pipe.fileHandleForReading.close()
                    try? pipe.fileHandleForWriting.close()
                }
                let descriptor = pipe.fileHandleForReading.fileDescriptor
                guard fcntl(descriptor, F_SETFL, O_NONBLOCK) != -1 else {
                    throw CocoaError(.fileReadUnknown)
                }
                var outputData = Data()
                var outputWasTruncated = false
                // Drain incrementally; neither disk usage nor retained memory grows with output.
                func drainOutput() {
                    var buffer = [UInt8](repeating: 0, count: 8192)
                    for _ in 0..<32 {
                        let count = Darwin.read(descriptor, &buffer, buffer.count)
                        guard count > 0 else { break }
                        outputData.append(contentsOf: buffer.prefix(count))
                        if outputData.count > maximumOutputBytes {
                            outputData.removeFirst(outputData.count - maximumOutputBytes)
                            outputWasTruncated = true
                        }
                    }
                }
                var attributes: posix_spawnattr_t?
                var actions: posix_spawn_file_actions_t?
                func checked(_ result: Int32) throws {
                    if result != 0 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(result)) }
                }
                try checked(posix_spawnattr_init(&attributes))
                defer { posix_spawnattr_destroy(&attributes) }
                try checked(posix_spawn_file_actions_init(&actions))
                defer { posix_spawn_file_actions_destroy(&actions) }
                // A new process group is established atomically at spawn, before any
                // project code can create children. Never signal the editor's group.
                try checked(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
                try checked(posix_spawnattr_setpgroup(&attributes, 0))
                try checked(posix_spawn_file_actions_addchdir(&actions, plan.workingDirectoryURL.path))
                try checked(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
                let writer = pipe.fileHandleForWriting.fileDescriptor
                try checked(posix_spawn_file_actions_adddup2(&actions, writer, STDOUT_FILENO))
                try checked(posix_spawn_file_actions_adddup2(&actions, writer, STDERR_FILENO))
                let arguments = ([plan.executableURL.path] + plan.arguments).map { strdup($0) }
                let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
                defer {
                    arguments.forEach { free($0) }
                    environment.forEach { free($0) }
                }
                guard arguments.allSatisfy({ $0 != nil }), environment.allSatisfy({ $0 != nil }) else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOMEM))
                }
                var argv = arguments + [nil]
                var envp = environment + [nil]
                var processID: pid_t = 0
                try Task.checkCancellation()
                try checked(posix_spawn(&processID, plan.executableURL.path, &actions, &attributes, &argv, &envp))
                // Also stop ordinary background children when their driver exits.
                // A project can deliberately detach with setsid; that is not contained.
                defer { _ = Darwin.kill(-processID, SIGKILL) }
                try? pipe.fileHandleForWriting.close()

                let clock = ContinuousClock()
                let deadline = clock.now.advanced(by: .seconds(max(1, min(timeout, 600))))
                var didTimeOut = false
                var wasCancelled = false
                var waitStatus: Int32 = 0
                var reaped = false
                func pollExit() -> Bool {
                    let result = waitpid(processID, &waitStatus, WNOHANG)
                    if result == processID { reaped = true; return true }
                    return result == -1 && errno != EINTR
                }
                while !pollExit() {
                    drainOutput()
                    if Task.isCancelled || clock.now >= deadline {
                        wasCancelled = Task.isCancelled
                        didTimeOut = !wasCancelled && clock.now >= deadline
                        // SIGTERM can be ignored. Stop the owned group and bound reaping.
                        _ = Darwin.kill(-processID, SIGKILL)
                        let reapDeadline = clock.now.advanced(by: .seconds(1))
                        while !pollExit() && clock.now < reapDeadline {
                            drainOutput()
                            await Task.detached {
                                try? await Task.sleep(for: .milliseconds(20))
                            }.value
                        }
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                drainOutput()
                let signal = waitStatus & 0x7f
                let status: Int32 = !reaped ? -1 : (signal == 0 ? (waitStatus >> 8) & 0xff : 128 + signal)
                var output = String(decoding: outputData, as: UTF8.self)
                if outputWasTruncated {
                    output = "… Earlier output was truncated …\n" + output
                }
                if output.isEmpty {
                    output = status == 0 ? "Verification completed without output." : "Verification failed without output."
                }
                if wasCancelled { output += "\nVerification cancelled." }
                if didTimeOut { output += "\nVerification timed out." }
                return .init(
                    plan: plan,
                    terminationStatus: status,
                    output: output,
                    didTimeOut: didTimeOut,
                    wasCancelled: wasCancelled
                )
            } catch {
                return .init(
                    plan: plan,
                    terminationStatus: -1,
                    output: error is CancellationError ? "Verification cancelled before launch." : error.localizedDescription,
                    didTimeOut: false,
                    wasCancelled: error is CancellationError
                )
            }
        }
        return await withTaskCancellationHandler {
            await verificationTask.value
        } onCancel: {
            verificationTask.cancel()
        }
#endif
    }
}

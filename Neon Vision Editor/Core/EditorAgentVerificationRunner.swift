import Foundation
#if os(macOS)
import Security
#endif

nonisolated struct EditorAgentVerificationResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let plan: EditorAgentVerificationPlan
    let terminationStatus: Int32
    let output: String
    let didTimeOut: Bool

    var succeeded: Bool {
        terminationStatus == 0 && !didTimeOut
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

        let verificationTask: Task<EditorAgentVerificationResult, Never> = Task.detached(priority: .userInitiated) {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("NeonEditorAgentVerification-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            defer { try? FileManager.default.removeItem(at: outputURL) }

            do {
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                defer { try? outputHandle.close() }
                let process = Process()
                process.executableURL = plan.executableURL
                process.arguments = plan.arguments
                process.currentDirectoryURL = plan.workingDirectoryURL
                process.standardOutput = outputHandle
                process.standardError = outputHandle
                try process.run()

                let deadline = Date().addingTimeInterval(max(1, min(timeout, 600)))
                var didTimeOut = false
                while process.isRunning {
                    if Task.isCancelled || Date() >= deadline {
                        didTimeOut = Date() >= deadline
                        process.terminate()
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                process.waitUntilExit()
                try? outputHandle.synchronize()
                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let boundedData = data.suffix(maximumOutputBytes)
                var output = String(decoding: boundedData, as: UTF8.self)
                if data.count > maximumOutputBytes {
                    output = "… Earlier output was truncated …\n" + output
                }
                if output.isEmpty {
                    output = process.terminationStatus == 0 ? "Verification completed without output." : "Verification failed without output."
                }
                return .init(
                    plan: plan,
                    terminationStatus: process.terminationStatus,
                    output: output,
                    didTimeOut: didTimeOut
                )
            } catch {
                return .init(
                    plan: plan,
                    terminationStatus: -1,
                    output: error.localizedDescription,
                    didTimeOut: false
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

import SwiftUI
import Foundation

#if os(macOS)
struct IntegratedTerminalContent: View {
    private static let maxOutputUTF16Length = 240_000

    let rootFolderURL: URL?
    @Binding var command: String
    @Binding var output: String
    @Binding var isRunning: Bool
    var showsCloseButton: Bool = false
    var onClose: (() -> Void)? = nil
    @State private var workingDirectoryOverride: URL? = nil

    private var workingDirectory: URL {
        workingDirectoryOverride ?? rootFolderURL ?? FileManager.default.homeDirectoryForCurrentUser
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Terminal", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                workingDirectoryMenu
                Text(workingDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsCloseButton {
                    Button("Close") { onClose?() }
                        .keyboardShortcut(.cancelAction)
                }
            }

            ScrollView {
                Text(output.isEmpty ? "Ready." : output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(runCommand)
                    .disabled(isRunning)
                    .accessibilityLabel("Terminal command")
                Button {
                    runCommand()
                } label: {
                    Label(isRunning ? "Running" : "Run", systemImage: isRunning ? "hourglass" : "play.fill")
                }
                .disabled(isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
                Button {
                    output = ""
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(output.isEmpty || isRunning)

                Button {
                    command = ""
                    output = "Ready.\n"
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
                .disabled(isRunning)
            }
        }
        .padding(showsCloseButton ? 18 : 12)
    }

    private var workingDirectoryMenu: some View {
        Menu {
            if let rootFolderURL {
                Button {
                    workingDirectoryOverride = rootFolderURL
                } label: {
                    Label("Project Root", systemImage: "folder")
                }
            }
            Button {
                workingDirectoryOverride = FileManager.default.homeDirectoryForCurrentUser
            } label: {
                Label("Home", systemImage: "house")
            }
            Button {
                workingDirectoryOverride = nil
            } label: {
                Label("Default", systemImage: "arrow.uturn.backward")
            }
        } label: {
            Image(systemName: "folder.badge.gearshape")
        }
        .help("Terminal Working Directory")
        .accessibilityLabel("Terminal working directory")
    }

    private func runCommand() {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }
        let directory = workingDirectory
        isRunning = true
        appendOutput("\(directory.path)$ \(trimmed)\n")
        command = ""

        Task {
            let status = await Self.runShellCommand(trimmed, in: directory) { chunk in
                Task { @MainActor in
                    appendOutput(chunk)
                }
            }
            if let status, status != 0 {
                appendOutput("\n[exit \(status)]\n")
            }
            isRunning = false
        }
    }

    @MainActor
    private func appendOutput(_ chunk: String) {
        output += chunk
        guard output.utf16.count > Self.maxOutputUTF16Length else { return }
        let trimTarget = output.utf16.count - Self.maxOutputUTF16Length
        let trimIndex = output.utf16.index(output.utf16.startIndex, offsetBy: trimTarget)
        if let stringIndex = String.Index(trimIndex, within: output) {
            output = "[terminal output truncated]\n" + output[stringIndex...]
        } else {
            output = "[terminal output truncated]\n" + String(output.suffix(Self.maxOutputUTF16Length / 2))
        }
    }

    private nonisolated static func runShellCommand(
        _ command: String,
        in directory: URL,
        onOutput: @Sendable @escaping (String) -> Void
    ) async -> Int32? {
        await Task.detached(priority: .userInitiated) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", command]
            process.currentDirectoryURL = directory
            process.standardOutput = pipe
            process.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                guard let text = String(data: handle.availableData, encoding: .utf8), text.isEmpty == false else {
                    return
                }
                onOutput(text)
            }
            defer {
                pipe.fileHandleForReading.readabilityHandler = nil
            }

            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                onOutput("Failed to run command: \(error.localizedDescription)\n")
                return nil
            }
        }.value
    }
}
#endif

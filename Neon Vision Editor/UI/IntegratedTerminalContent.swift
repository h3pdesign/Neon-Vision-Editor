import SwiftUI
import Foundation
import Combine

#if os(macOS)
@MainActor
final class IntegratedTerminalSession: ObservableObject {
    private static let maxOutputUTF16Length = 240_000

    @Published var output: String = ""
    @Published var isRunning: Bool = false

    private var shellProcess: Process?
    private var shellInputPipe: Pipe?
    private var shellOutputPipe: Pipe?
    private var generation: Int = 0

    deinit {
        shellOutputPipe?.fileHandleForReading.readabilityHandler = nil
        shellInputPipe?.fileHandleForWriting.closeFile()
        if shellProcess?.isRunning == true {
            shellProcess?.terminate()
        }
    }

    func startIfNeeded(in directory: URL) {
        if shellProcess?.isRunning == true {
            isRunning = true
            return
        }

        generation += 1
        let currentGeneration = generation
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = []
        process.currentDirectoryURL = directory

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        environment["CLICOLOR"] = "1"
        environment["FORCE_COLOR"] = "1"
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.appendOutput(text)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                outputPipe.fileHandleForReading.readabilityHandler = nil
                self.isRunning = false
                self.shellProcess = nil
                self.shellInputPipe = nil
                self.shellOutputPipe = nil
                self.appendOutput("\n[terminal exited \(process.terminationStatus)]\n")
            }
        }

        do {
            try process.run()
            shellProcess = process
            shellInputPipe = inputPipe
            shellOutputPipe = outputPipe
            isRunning = true
            if output == "Ready." {
                output = ""
            }
            appendOutput("Started zsh in \(directory.path)\n")
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            isRunning = false
            appendOutput("Failed to start terminal: \(error.localizedDescription)\n")
        }
    }

    func send(_ command: String, in directory: URL) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startIfNeeded(in: directory)
        guard let input = shellInputPipe?.fileHandleForWriting else {
            appendOutput("Terminal is not ready.\n")
            return
        }
        appendOutput("$ \(trimmed)\n")
        if let data = "\(trimmed)\n".data(using: .utf8) {
            input.write(data)
        }
    }

    func clear() {
        output = ""
    }

    func restart(in directory: URL) {
        stop()
        output = ""
        startIfNeeded(in: directory)
    }

    private func stop() {
        generation += 1
        shellOutputPipe?.fileHandleForReading.readabilityHandler = nil
        shellInputPipe?.fileHandleForWriting.closeFile()
        if shellProcess?.isRunning == true {
            shellProcess?.terminate()
        }
        shellProcess = nil
        shellInputPipe = nil
        shellOutputPipe = nil
        isRunning = false
    }

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
}

@MainActor
struct IntegratedTerminalContent: View {
    let rootFolderURL: URL?
    @ObservedObject var session: IntegratedTerminalSession
    var showsCloseButton: Bool = false
    var onClose: (() -> Void)? = nil
    @State private var command: String = ""
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
                terminalStatusLabel
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
                Text(session.output.isEmpty ? "Ready." : session.output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                TextField("Command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(sendCommand)
                    .disabled(!session.isRunning)
                    .accessibilityLabel("Terminal command")

                Button {
                    sendCommand()
                } label: {
                    Label("Send", systemImage: "paperplane.fill")
                }
                .disabled(!session.isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)

                Button {
                    session.clear()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(session.output.isEmpty)

                Button {
                    command = ""
                    session.restart(in: workingDirectory)
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(showsCloseButton ? 18 : 12)
        .onAppear {
            session.startIfNeeded(in: workingDirectory)
        }
        .onChange(of: workingDirectory) { _, newValue in
            command = ""
            session.restart(in: newValue)
        }
    }

    private var terminalStatusLabel: some View {
        Label(session.isRunning ? "Live" : "Stopped", systemImage: session.isRunning ? "circle.fill" : "circle")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(session.isRunning ? Color.green : Color.secondary)
            .labelStyle(.titleAndIcon)
            .help(session.isRunning ? "Persistent shell is running" : "Terminal shell is stopped")
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

    private func sendCommand() {
        session.send(command, in: workingDirectory)
        command = ""
    }
}
#endif

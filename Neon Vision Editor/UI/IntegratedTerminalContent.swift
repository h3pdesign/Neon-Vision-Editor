import SwiftUI
import Foundation
import Combine
import Darwin

#if os(macOS)
@MainActor
final class IntegratedTerminalSession: ObservableObject {
    private static let maxOutputUTF16Length = 240_000

    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published private(set) var usesPTY: Bool = false

    private var shellProcess: Process?
    private var masterTerminalHandle: FileHandle?
    private var masterTerminalFileDescriptor: Int32 = -1
    private var generation: Int = 0

    deinit {
        masterTerminalHandle?.readabilityHandler = nil
        masterTerminalHandle?.closeFile()
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
        guard let terminal = openTerminalPair() else {
            isRunning = false
            usesPTY = false
            appendOutput("Failed to allocate a terminal session.\n")
            return
        }
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l"]
        process.currentDirectoryURL = directory

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["CLICOLOR"] = "1"
        environment["FORCE_COLOR"] = "1"
        environment["TERM_PROGRAM"] = "Neon Vision Editor"
        process.environment = environment
        process.standardInput = terminal.slaveHandle
        process.standardOutput = terminal.slaveHandle
        process.standardError = terminal.slaveHandle

        terminal.masterHandle.readabilityHandler = { [weak self] handle in
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
                terminal.masterHandle.readabilityHandler = nil
                self.isRunning = false
                self.usesPTY = false
                self.shellProcess = nil
                self.closeTerminalHandles()
                self.appendOutput("\n[terminal exited \(process.terminationStatus)]\n")
            }
        }

        do {
            try process.run()
            terminal.slaveHandle.closeFile()
            shellProcess = process
            masterTerminalHandle = terminal.masterHandle
            masterTerminalFileDescriptor = terminal.masterFileDescriptor
            isRunning = true
            usesPTY = true
            resize(columns: 120, rows: 36)
            if output == "Ready." {
                output = ""
            }
            appendOutput("Started PTY-backed zsh in \(directory.path)\n")
        } catch {
            terminal.masterHandle.readabilityHandler = nil
            terminal.masterHandle.closeFile()
            terminal.slaveHandle.closeFile()
            isRunning = false
            usesPTY = false
            appendOutput("Failed to start terminal: \(error.localizedDescription)\n")
        }
    }

    func send(_ command: String, in directory: URL) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startIfNeeded(in: directory)
        guard masterTerminalHandle != nil else {
            appendOutput("Terminal is not ready.\n")
            return
        }
        appendOutput("$ \(trimmed)\n")
        writeToTerminal("\(trimmed)\n")
    }

    func sendInterrupt() {
        writeToTerminal("\u{3}")
    }

    func sendEndOfTransmission() {
        writeToTerminal("\u{4}")
    }

    func resize(columns: Int, rows: Int) {
        guard masterTerminalFileDescriptor >= 0 else { return }
        var size = winsize(
            ws_row: UInt16(clamping: rows),
            ws_col: UInt16(clamping: columns),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        _ = ioctl(masterTerminalFileDescriptor, TIOCSWINSZ, &size)
    }

    func clear() {
        output = ""
    }

    func restart(in directory: URL) {
        stop()
        output = ""
        startIfNeeded(in: directory)
    }

    func stop() {
        generation += 1
        masterTerminalHandle?.readabilityHandler = nil
        if shellProcess?.isRunning == true {
            shellProcess?.terminate()
        }
        shellProcess = nil
        closeTerminalHandles()
        isRunning = false
        usesPTY = false
    }

    private func openTerminalPair() -> (masterHandle: FileHandle, slaveHandle: FileHandle, masterFileDescriptor: Int32)? {
        var masterFileDescriptor: Int32 = -1
        var slaveFileDescriptor: Int32 = -1
        guard openpty(&masterFileDescriptor, &slaveFileDescriptor, nil, nil, nil) == 0 else {
            return nil
        }
        return (
            FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true),
            FileHandle(fileDescriptor: slaveFileDescriptor, closeOnDealloc: true),
            masterFileDescriptor
        )
    }

    private func closeTerminalHandles() {
        masterTerminalHandle?.readabilityHandler = nil
        masterTerminalHandle?.closeFile()
        masterTerminalHandle = nil
        masterTerminalFileDescriptor = -1
    }

    private func writeToTerminal(_ text: String) {
        guard let data = text.data(using: .utf8), let masterTerminalHandle else { return }
        masterTerminalHandle.write(data)
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
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { resizeTerminal(for: proxy.size) }
                        .onChange(of: proxy.size) { _, newSize in resizeTerminal(for: newSize) }
                }
            }

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

                Button {
                    session.sendInterrupt()
                } label: {
                    Label("Interrupt", systemImage: "stop.circle")
                }
                .disabled(!session.isRunning)
                .help("Send Control-C")

                Button {
                    session.sendEndOfTransmission()
                } label: {
                    Label("End Input", systemImage: "eject")
                }
                .disabled(!session.isRunning)
                .help("Send Control-D")
            }

            Text("PTY-backed shell. ANSI styling and full-screen terminal apps are not yet rendered.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        Label(session.isRunning ? (session.usesPTY ? "PTY Live" : "Live") : "Stopped", systemImage: session.isRunning ? "circle.fill" : "circle")
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

    private func resizeTerminal(for size: CGSize) {
        let characterWidth: CGFloat = 8
        let lineHeight: CGFloat = 17
        let columns = max(20, Int(size.width / characterWidth))
        let rows = max(4, Int(size.height / lineHeight))
        session.resize(columns: columns, rows: rows)
    }
}
#endif

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

    private var shellProcessID: pid_t = -1
    private var masterTerminalHandle: FileHandle?
    private var masterTerminalFileDescriptor: Int32 = -1
    private var generation: Int = 0
    private var displaySanitizer = TerminalDisplaySanitizer()

    deinit {
        masterTerminalHandle?.readabilityHandler = nil
        masterTerminalHandle?.closeFile()
        if shellProcessID > 0 {
            kill(shellProcessID, SIGTERM)
        }
    }

    func startIfNeeded(in directory: URL) {
        if shellProcessID > 0 {
            isRunning = true
            return
        }

        generation += 1
        let currentGeneration = generation
        var masterFileDescriptor: Int32 = -1
        let processID = forkpty(&masterFileDescriptor, nil, nil, nil)
        guard processID >= 0 else {
            isRunning = false
            usesPTY = false
            appendOutput("Failed to allocate a terminal session.\n")
            return
        }

        if processID == 0 {
            _ = setsid()
            _ = ioctl(STDIN_FILENO, TIOCSCTTY, 0)
            _ = setpgid(0, 0)
            _ = tcsetpgrp(STDIN_FILENO, getpid())
            _ = chdir(directory.path)
            setenv("TERM", "xterm-256color", 1)
            setenv("CLICOLOR", "1", 1)
            setenv("FORCE_COLOR", "1", 1)
            setenv("TERM_PROGRAM", "Neon Vision Editor", 1)
            var arguments: [UnsafeMutablePointer<CChar>?] = [
                strdup("zsh"),
                strdup("-l"),
                strdup("-o"),
                strdup("NO_MONITOR"),
                nil
            ]
            arguments.withUnsafeMutableBufferPointer {
                _ = execv("/bin/zsh", $0.baseAddress)
            }
            _exit(127)
        }

        let masterHandle = FileHandle(fileDescriptor: masterFileDescriptor, closeOnDealloc: true)

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.appendOutput(text)
            }
        }
        shellProcessID = processID
        masterTerminalHandle = masterHandle
        masterTerminalFileDescriptor = masterFileDescriptor
        isRunning = true
        usesPTY = true
        resize(columns: 120, rows: 36)
        if output == "Ready." {
            output = ""
        }
        appendOutput("Started PTY-backed zsh in \(directory.path)\n")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            _ = waitpid(processID, &status, 0)
            let exitStatus = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : 128 + (status & 0x7F)
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == currentGeneration,
                      self.shellProcessID == processID else { return }
                self.masterTerminalHandle?.readabilityHandler = nil
                self.isRunning = false
                self.usesPTY = false
                self.shellProcessID = -1
                self.closeTerminalHandles()
                self.appendOutput("\n[terminal exited \(exitStatus)]\n")
            }
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
        displaySanitizer.reset()
    }

    func restart(in directory: URL) {
        stop()
        output = ""
        displaySanitizer.reset()
        startIfNeeded(in: directory)
    }

    func stop() {
        generation += 1
        masterTerminalHandle?.readabilityHandler = nil
        if shellProcessID > 0 {
            kill(shellProcessID, SIGTERM)
        }
        shellProcessID = -1
        closeTerminalHandles()
        isRunning = false
        usesPTY = false
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
        output += displaySanitizer.displayText(from: chunk)
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

/// The panel intentionally renders scrollback as text rather than a terminal grid.
/// Remove control sequences so supported shell output remains readable.
final class TerminalDisplaySanitizer {
    private enum State {
        case text
        case escape
        case controlSequence
        case operatingSystemCommand
        case operatingSystemEscape
    }

    private var state: State = .text

    func reset() {
        state = .text
    }

    func displayText(from input: String) -> String {
        var output = ""
        for scalar in input.unicodeScalars {
            switch state {
            case .text:
                switch scalar.value {
                case 0x1B:
                    state = .escape
                case 0x08, 0x7F:
                    if !output.isEmpty { output.removeLast() }
                case 0x0D:
                    continue
                case 0x00...0x08, 0x0B...0x1F:
                    continue
                default:
                    output.unicodeScalars.append(scalar)
                }
            case .escape:
                switch scalar {
                case "[": state = .controlSequence
                case "]": state = .operatingSystemCommand
                default: state = .text
                }
            case .controlSequence:
                if (0x40...0x7E).contains(scalar.value) {
                    state = .text
                }
            case .operatingSystemCommand:
                if scalar.value == 0x07 {
                    state = .text
                } else if scalar.value == 0x1B {
                    state = .operatingSystemEscape
                }
            case .operatingSystemEscape:
                state = scalar == "\\" ? .text : .operatingSystemCommand
            }
        }
        return output
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
    @FocusState private var commandFieldIsFocused: Bool

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

            HStack(spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Command")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Type a command and press Return", text: $command, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(sendCommand)
                        .disabled(!session.isRunning)
                        .focused($commandFieldIsFocused)
                        .accessibilityLabel("Terminal command")
                        .accessibilityHint("Type a command and press Return to send it to the terminal")

                    Button {
                        sendCommand()
                    } label: {
                        Label("Run", systemImage: "return")
                    }
                    .disabled(!session.isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }

            Text("Persistent shell. Commands run in the selected project folder. Full-screen terminal apps are not supported.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(showsCloseButton ? 18 : 12)
        .onAppear {
            session.startIfNeeded(in: workingDirectory)
            commandFieldIsFocused = true
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
        commandFieldIsFocused = true
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

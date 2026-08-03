import SwiftUI
import Foundation
import Combine
import Darwin

#if os(macOS) && !APP_STORE_BUILD
@MainActor
final class IntegratedTerminalSession: ObservableObject {
    private static let maxOutputUTF16Length = 240_000

    @Published var output: String = ""
    @Published var styledOutput: NSAttributedString = NSAttributedString(string: "")
    @Published var isRunning: Bool = false
    @Published private(set) var usesPTY: Bool = false

    private var shellProcessID: pid_t = -1
    private var masterTerminalHandle: FileHandle?
    private var masterTerminalFileDescriptor: Int32 = -1
    private var generation: Int = 0
    private var displaySanitizer = TerminalDisplaySanitizer()
    private var ansiFormatter = TerminalANSIFormatter()

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
        styledOutput = NSAttributedString(string: "")
        displaySanitizer.reset()
        ansiFormatter.reset()
    }

    func restart(in directory: URL) {
        stop()
        output = ""
        styledOutput = NSAttributedString(string: "")
        displaySanitizer.reset()
        ansiFormatter.reset()
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
        let displayChunk = displaySanitizer.displayText(from: chunk)
        output += displayChunk
        let styledChunk = ansiFormatter.attributedText(from: chunk)
        let combinedOutput = NSMutableAttributedString(attributedString: styledOutput)
        combinedOutput.append(styledChunk)
        styledOutput = combinedOutput
        guard output.utf16.count > Self.maxOutputUTF16Length else { return }
        let trimTarget = output.utf16.count - Self.maxOutputUTF16Length
        let trimIndex = output.utf16.index(output.utf16.startIndex, offsetBy: trimTarget)
        if let stringIndex = String.Index(trimIndex, within: output) {
            output = "[terminal output truncated]\n" + output[stringIndex...]
        } else {
            output = "[terminal output truncated]\n" + String(output.suffix(Self.maxOutputUTF16Length / 2))
        }
        if styledOutput.length > Self.maxOutputUTF16Length {
            let styledTrimTarget = styledOutput.length - Self.maxOutputUTF16Length
            let trimmed = NSMutableAttributedString(attributedString: styledOutput)
            trimmed.deleteCharacters(in: NSRange(location: 0, length: styledTrimTarget))
            styledOutput = trimmed
        }
    }
}

#endif

enum PythonRuntimeResolver {
    static let commonInterpreterPaths = [
        "/usr/bin/python3",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/opt/homebrew/bin/python",
        "/usr/local/bin/python"
    ]

    static func resolvedInterpreter(preferredPath: String, workingDirectory: URL? = nil) -> String? {
        let preferred = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let projectInterpreters = workingDirectory.flatMap { directory in
            [
                directory.appendingPathComponent(".venv/bin/python").path,
                directory.appendingPathComponent(".venv/bin/python3").path,
                directory.appendingPathComponent("venv/bin/python").path,
                directory.appendingPathComponent("venv/bin/python3").path
            ]
        } ?? []
        let candidates = (preferred.isEmpty ? [] : [preferred]) + projectInterpreters + commonInterpreterPaths
        for candidate in candidates {
            let expanded = NSString(string: candidate).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
        }
        return nil
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

#if os(macOS) && !APP_STORE_BUILD
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

/// Converts terminal SGR color sequences into attributes while preserving state across PTY chunks.
final class TerminalANSIFormatter {
    private var state: State = .text
    private var foregroundColor: NSColor?
    private var backgroundColor: NSColor?
    private var isBold = false

    private enum State {
        case text
        case escape
        case controlSequence(String)
        case operatingSystemCommand
        case operatingSystemEscape
    }

    func reset() {
        state = .text
        foregroundColor = nil
        backgroundColor = nil
        isBold = false
    }

    func attributedText(from input: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        var textBuffer = String()

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let foregroundColor {
                attributes[.foregroundColor] = foregroundColor
            }
            if let backgroundColor {
                attributes[.backgroundColor] = backgroundColor
            }
            if isBold {
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
            }
            output.append(NSAttributedString(string: textBuffer, attributes: attributes))
            textBuffer.removeAll(keepingCapacity: true)
        }

        for scalar in input.unicodeScalars {
            switch state {
            case .text:
                switch scalar.value {
                case 0x1B:
                    flushText()
                    state = .escape
                case 0x0D, 0x08, 0x7F:
                    flushText()
                case 0x00...0x08, 0x0B...0x1F:
                    flushText()
                default:
                    textBuffer.unicodeScalars.append(scalar)
                }
            case .escape:
                switch scalar {
                case "[": state = .controlSequence("")
                case "]": state = .operatingSystemCommand
                default: state = .text
                }
            case .controlSequence(let sequence):
                if (0x40...0x7E).contains(scalar.value) {
                    if scalar == "m" {
                        applySGR(sequence)
                    }
                    state = .text
                } else {
                    state = .controlSequence(sequence + String(scalar))
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
        flushText()
        return output
    }

    private func applySGR(_ sequence: String) {
        let values = sequence.isEmpty
            ? [0]
            : sequence.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var index = 0
        while index < values.count {
            let value = values[index]
            switch value {
            case 0:
                foregroundColor = nil
                backgroundColor = nil
                isBold = false
            case 1:
                isBold = true
            case 22:
                isBold = false
            case 39:
                foregroundColor = nil
            case 49:
                backgroundColor = nil
            case 30...37:
                foregroundColor = color(for: value - 30, bright: isBold)
            case 40...47:
                backgroundColor = color(for: value - 40, bright: false)
            case 90...97:
                foregroundColor = color(for: value - 90, bright: true)
            case 100...107:
                backgroundColor = color(for: value - 100, bright: true)
            case 38, 48:
                let isForeground = value == 38
                if index + 1 < values.count {
                    switch values[index + 1] {
                    case 5 where index + 2 < values.count:
                        let color = color256(values[index + 2])
                        if isForeground { foregroundColor = color } else { backgroundColor = color }
                        index += 2
                    case 2 where index + 4 < values.count:
                        let color = NSColor(
                            calibratedRed: CGFloat(values[index + 2]) / 255,
                            green: CGFloat(values[index + 3]) / 255,
                            blue: CGFloat(values[index + 4]) / 255,
                            alpha: 1
                        )
                        if isForeground { foregroundColor = color } else { backgroundColor = color }
                        index += 4
                    default:
                        break
                    }
                }
            default:
                break
            }
            index += 1
        }
    }

    private func color(for index: Int, bright: Bool) -> NSColor {
        let palette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.10, 0.10), (0.80, 0.12, 0.12), (0.20, 0.65, 0.25), (0.80, 0.55, 0.10),
            (0.20, 0.40, 0.85), (0.70, 0.25, 0.75), (0.10, 0.65, 0.70), (0.80, 0.80, 0.80)
        ]
        let brightPalette: [(CGFloat, CGFloat, CGFloat)] = [
            (0.35, 0.35, 0.35), (1.00, 0.30, 0.30), (0.35, 0.90, 0.40), (1.00, 0.80, 0.25),
            (0.40, 0.60, 1.00), (0.90, 0.45, 0.95), (0.30, 0.90, 0.95), (1.00, 1.00, 1.00)
        ]
        let components = (bright ? brightPalette : palette)[max(0, min(index, 7))]
        return NSColor(calibratedRed: components.0, green: components.1, blue: components.2, alpha: 1)
    }

    private func color256(_ index: Int) -> NSColor {
        if index < 8 { return color(for: index, bright: false) }
        if index < 16 { return color(for: index - 8, bright: true) }
        if index < 232 {
            let adjusted = index - 16
            let red = adjusted / 36
            let green = (adjusted % 36) / 6
            let blue = adjusted % 6
            func component(_ value: Int) -> CGFloat { value == 0 ? 0 : CGFloat(55 + value * 40) / 255 }
            return NSColor(calibratedRed: component(red), green: component(green), blue: component(blue), alpha: 1)
        }
        let gray = CGFloat(8 + (index - 232) * 10) / 255
        return NSColor(calibratedWhite: gray, alpha: 1)
    }
}

@MainActor
struct IntegratedTerminalContent: View {
    let rootFolderURL: URL?
    @ObservedObject var session: IntegratedTerminalSession
    var selectedFileURL: URL? = nil
    var showsCloseButton: Bool = false
    var onClose: (() -> Void)? = nil
    @State private var command: String = ""
    @State private var workingDirectoryOverride: URL? = nil
    @FocusState private var commandFieldIsFocused: Bool
    @AppStorage(SettingsPreferenceKey.pythonInterpreterPath) private var pythonInterpreterPath: String = ""

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

            ScrollView([.vertical, .horizontal]) {
                Text(AttributedString(session.styledOutput.length == 0
                    ? NSAttributedString(string: "Ready.")
                    : session.styledOutput))
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: true, vertical: false)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
#if os(macOS)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
#else
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
#endif
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { resizeTerminal(for: proxy.size) }
                        .onChange(of: proxy.size) { _, newSize in resizeTerminal(for: newSize) }
                }
            }

            HStack(spacing: 8) {
                if isPythonFileSelected {
                    Button {
                        runSelectedPythonFile()
                    } label: {
                        Label("Run Python", systemImage: "play.fill")
                    }
                    .disabled(!session.isRunning || pythonInterpreter == nil)
                    .help(pythonInterpreter == nil ? "Configure a Python interpreter in Settings" : "Run the selected Python file")
                    .accessibilityLabel("Run Python file")
                    .accessibilityHint("Runs the selected Python file in the integrated terminal")
                }

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
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Type a command and press Return", text: $command, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
#if os(iOS)
                        .lineLimit(1...4)
#else
                        .lineLimit(1...6)
#endif
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .top)
                        .onSubmit(sendCommand)
                        .disabled(!session.isRunning)
                        .focused($commandFieldIsFocused)
                        .accessibilityLabel("Terminal command")
                        .accessibilityHint("Enter a command or input line. Press Return to send it to the terminal.")

                    Button {
                        sendCommand()
                    } label: {
                        Image(systemName: "return")
                    }
                    .buttonStyle(.borderedProminent)
#if os(iOS)
                    .frame(width: 44, height: 44)
#else
                    .frame(width: 52, height: 52)
#endif
                    .disabled(!session.isRunning || command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Run terminal command")
                    .accessibilityHint("Send the command directly to the terminal")
#if os(macOS)
                    .keyboardShortcut(.return, modifiers: [.command])
#endif
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

    private var isPythonFileSelected: Bool {
        selectedFileURL?.isFileURL == true && selectedFileURL?.pathExtension.lowercased() == "py"
    }

    private var pythonInterpreter: String? {
        PythonRuntimeResolver.resolvedInterpreter(preferredPath: pythonInterpreterPath, workingDirectory: workingDirectory)
    }

    private func runSelectedPythonFile() {
        guard let selectedFileURL,
              isPythonFileSelected,
              let pythonInterpreter else { return }
        let command = "PYTHONUNBUFFERED=1 \(PythonRuntimeResolver.shellQuote(pythonInterpreter)) -u \(PythonRuntimeResolver.shellQuote(selectedFileURL.path))"
        session.send(command, in: workingDirectory)
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

import SwiftUI
import Foundation
import Combine
import Darwin

#if os(macOS) && !APP_STORE_BUILD
nonisolated struct TerminalProcessedOutput: @unchecked Sendable {
    let displayText: String
    let styledText: NSAttributedString
}

nonisolated enum TerminalOutputCommand: Sendable {
    case reset
    case chunk(String, generation: Int)
}

struct TerminalRenderUpdate {
    enum Kind {
        case reset
        case append(NSAttributedString)
    }

    let revision: Int
    let kind: Kind
}

@MainActor
final class IntegratedTerminalSession: ObservableObject {
    static let maxOutputUTF16Length = 240_000
    nonisolated private static let processGroupTerminationGracePeriod: TimeInterval = 0.5

    @Published var isRunning: Bool = false
    @Published private(set) var usesPTY: Bool = false
    @Published private(set) var isOutputEmpty: Bool = true
    @Published private(set) var renderUpdate = TerminalRenderUpdate(revision: 0, kind: .reset)

    var output: String {
        String(outputBuffer)
    }

    private var shellProcessID: pid_t = -1
    private var masterTerminalHandle: FileHandle?
    private var masterTerminalFileDescriptor: Int32 = -1
    private var generation: Int = 0
    private let outputBuffer = NSMutableString()
    private let renderedStyledOutput = NSMutableAttributedString()
    private let pendingStyledOutput = NSMutableAttributedString()
    private var outputPublishWorkItem: DispatchWorkItem?
    private var renderRevision = 0
    private let outputContinuation: AsyncStream<TerminalOutputCommand>.Continuation
    private var outputProcessingTask: Task<Void, Never>?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: TerminalOutputCommand.self)
        outputContinuation = continuation
        outputProcessingTask = Task.detached(priority: .userInitiated) { [weak self] in
            let displaySanitizer = TerminalDisplaySanitizer()
            let ansiFormatter = TerminalANSIFormatter()
            for await command in stream {
                guard !Task.isCancelled else { break }
                switch command {
                case .reset:
                    displaySanitizer.reset()
                    ansiFormatter.reset()
                case .chunk(let text, let generation):
                    let processed = TerminalProcessedOutput(
                        displayText: displaySanitizer.displayText(from: text),
                        styledText: ansiFormatter.attributedText(from: text)
                    )
                    await self?.appendProcessedOutput(processed, generation: generation)
                }
            }
        }
    }

    deinit {
        outputContinuation.finish()
        outputProcessingTask?.cancel()
        masterTerminalHandle?.readabilityHandler = nil
        masterTerminalHandle?.closeFile()
        Self.terminateProcessGroup(shellProcessID)
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
            enqueueOutput("Failed to allocate a terminal session.\n", generation: currentGeneration)
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

        outputContinuation.yield(.reset)
        let outputContinuation = outputContinuation
        masterHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            outputContinuation.yield(.chunk(text, generation: currentGeneration))
        }
        shellProcessID = processID
        masterTerminalHandle = masterHandle
        masterTerminalFileDescriptor = masterFileDescriptor
        isRunning = true
        usesPTY = true
        resize(columns: 120, rows: 36)
        enqueueOutput("Started PTY-backed zsh in \(directory.path)\n", generation: currentGeneration)

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
                self.enqueueOutput("\n[terminal exited \(exitStatus)]\n", generation: currentGeneration)
            }
        }
    }

    func send(_ command: String, in directory: URL) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        startIfNeeded(in: directory)
        guard masterTerminalHandle != nil else {
            enqueueOutput("Terminal is not ready.\n", generation: generation)
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
        resetOutput()
        outputContinuation.yield(.reset)
    }

    func restart(in directory: URL) {
        stop()
        resetOutput()
        startIfNeeded(in: directory)
    }

    func stop() {
        generation += 1
        masterTerminalHandle?.readabilityHandler = nil
        Self.terminateProcessGroup(shellProcessID)
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

    nonisolated private static func terminateProcessGroup(_ processID: pid_t) {
        guard processID > 0 else { return }
        // The child calls setsid/setpgid before exec. Signalling the process group
        // closes foreground commands as well as the interactive shell itself.
        guard kill(-processID, SIGTERM) == 0 else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + processGroupTerminationGracePeriod
        ) {
            // A child can ignore SIGTERM (for example, a development server).
            // Only escalate while the original process group still exists.
            guard kill(-processID, 0) == 0 else { return }
            _ = kill(-processID, SIGKILL)
        }
    }

    private func writeToTerminal(_ text: String) {
        guard let data = text.data(using: .utf8), let masterTerminalHandle else { return }
        masterTerminalHandle.write(data)
    }

    func styledOutputSnapshot() -> NSAttributedString {
        NSAttributedString(attributedString: renderedStyledOutput)
    }

    private func enqueueOutput(_ chunk: String, generation: Int) {
        outputContinuation.yield(.chunk(chunk, generation: generation))
    }

    private func appendProcessedOutput(_ processed: TerminalProcessedOutput, generation: Int) {
        guard self.generation == generation else { return }
        outputBuffer.append(processed.displayText)
        pendingStyledOutput.append(processed.styledText)
        if outputBuffer.length > Self.maxOutputUTF16Length {
            let trimTarget = outputBuffer.length - Self.maxOutputUTF16Length
            outputBuffer.deleteCharacters(in: NSRange(location: 0, length: trimTarget))
            outputBuffer.insert("[terminal output truncated]\n", at: 0)
        }
        if pendingStyledOutput.length > Self.maxOutputUTF16Length {
            let trimTarget = pendingStyledOutput.length - Self.maxOutputUTF16Length
            pendingStyledOutput.deleteCharacters(in: NSRange(location: 0, length: trimTarget))
        }
        if isOutputEmpty != (outputBuffer.length == 0) {
            isOutputEmpty = outputBuffer.length == 0
        }
        scheduleOutputPublication()
    }

    private func scheduleOutputPublication() {
        outputPublishWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.pendingStyledOutput.length > 0 else {
                self.outputPublishWorkItem = nil
                return
            }
            let appended = NSAttributedString(attributedString: self.pendingStyledOutput)
            self.pendingStyledOutput.setAttributedString(NSAttributedString(string: ""))
            self.renderedStyledOutput.append(appended)
            if self.renderedStyledOutput.length > Self.maxOutputUTF16Length {
                let trimTarget = self.renderedStyledOutput.length - Self.maxOutputUTF16Length
                self.renderedStyledOutput.deleteCharacters(in: NSRange(location: 0, length: trimTarget))
            }
            self.renderRevision += 1
            self.renderUpdate = TerminalRenderUpdate(revision: self.renderRevision, kind: .append(appended))
            self.outputPublishWorkItem = nil
        }
        outputPublishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.033, execute: workItem)
    }

    private func resetOutput() {
        outputPublishWorkItem?.cancel()
        outputPublishWorkItem = nil
        outputBuffer.setString("")
        pendingStyledOutput.setAttributedString(NSAttributedString(string: ""))
        renderedStyledOutput.setAttributedString(NSAttributedString(string: ""))
        isOutputEmpty = true
        renderRevision += 1
        renderUpdate = TerminalRenderUpdate(revision: renderRevision, kind: .reset)
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
nonisolated final class TerminalDisplaySanitizer {
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
nonisolated final class TerminalANSIFormatter {
    private var state: State = .text
    private var foregroundColor: NSColor?
    private var backgroundColor: NSColor?
    private var isBold = false
    private let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        return style.copy() as! NSParagraphStyle
    }()

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
            } else {
                attributes[.foregroundColor] = NSColor.textColor
            }
            if let backgroundColor {
                attributes[.backgroundColor] = backgroundColor
            }
            attributes[.font] = NSFont.monospacedSystemFont(
                ofSize: 12,
                weight: isBold ? .bold : .regular
            )
            attributes[.paragraphStyle] = paragraphStyle
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
struct TerminalOutputTextView: NSViewRepresentable {
    let session: IntegratedTerminalSession
    let update: TerminalRenderUpdate

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView(frame: scrollView.contentView.bounds)
        Self.configure(scrollView: scrollView, textView: textView)
        scrollView.documentView = textView

        context.coordinator.install(
            session.styledOutputSnapshot(),
            revision: update.revision,
            in: textView
        )
        return scrollView
    }

    static func configure(scrollView: NSScrollView, textView: NSTextView) {
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Terminal output")
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.apply(
            update,
            fallbackSnapshot: { session.styledOutputSnapshot() },
            in: textView
        )
    }

    final class Coordinator {
        private var appliedRevision = -1

        func install(_ snapshot: NSAttributedString, revision: Int, in textView: NSTextView) {
            appliedRevision = revision
            replaceContents(with: snapshot, in: textView)
        }

        func apply(
            _ update: TerminalRenderUpdate,
            fallbackSnapshot: () -> NSAttributedString,
            in textView: NSTextView
        ) {
            guard update.revision > appliedRevision else { return }
            switch update.kind {
            case .reset:
                replaceContents(with: fallbackSnapshot(), in: textView)
            case .append(let chunk) where update.revision == appliedRevision + 1:
                append(chunk, in: textView)
            case .append:
                // SwiftUI can coalesce observable updates. Rebuild only when an
                // intermediate append was skipped, never for the normal path.
                replaceContents(with: fallbackSnapshot(), in: textView)
            }
            appliedRevision = update.revision
        }

        private func replaceContents(with snapshot: NSAttributedString, in textView: NSTextView) {
            let contents = snapshot.length == 0
                ? NSAttributedString(
                    string: "Ready.",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                        .foregroundColor: NSColor.textColor
                    ]
                )
                : snapshot
            textView.textStorage?.setAttributedString(contents)
        }

        private func append(_ chunk: NSAttributedString, in textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            if storage.string == "Ready." {
                storage.setAttributedString(NSAttributedString(string: ""))
            }
            let visibleBottom = NSMaxY(textView.visibleRect)
            let wasNearBottom = visibleBottom >= textView.bounds.height - 24
            storage.append(chunk)
            if storage.length > IntegratedTerminalSession.maxOutputUTF16Length {
                storage.deleteCharacters(
                    in: NSRange(
                        location: 0,
                        length: storage.length - IntegratedTerminalSession.maxOutputUTF16Length
                    )
                )
            }
            if wasNearBottom, storage.length > 0 {
                textView.scrollRangeToVisible(NSRange(location: storage.length - 1, length: 1))
            }
        }
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

            TerminalOutputTextView(session: session, update: session.renderUpdate)
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
                .disabled(session.isOutputEmpty)

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

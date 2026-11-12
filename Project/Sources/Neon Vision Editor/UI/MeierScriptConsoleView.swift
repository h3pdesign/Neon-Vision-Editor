#if os(macOS) && !APP_STORE_BUILD
import SwiftUI

enum MeierScriptConsoleDefaults {
    static let visibleKey = "MeierScriptConsoleVisible"
    static let autoCheckKey = "MeierScriptAutoCheckEnabled"
    static let autoRunKey = "MeierScriptAutoRunEnabled"
    static let heightKey = "MeierScriptConsoleHeight"
    static let automaticDebounceNanoseconds: UInt64 = 600_000_000
    static let automaticRunTimeout: TimeInterval = 10
    static let manualRunTimeout: TimeInterval = 60
}

/// Per-window state of the MeierScript console. One script runs at a time; a
/// newer request cancels the previous process.
@MainActor
@Observable
final class MeierScriptConsoleModel {
    enum Phase: Equatable {
        case idle
        case checking
        case running
        case syntaxOK
        case syntaxError(MeierScriptLanguage.Diagnostic?)
        case finished(exitCode: Int32)
        case timedOut
        case cliMissing
    }

    private(set) var standardOutput = ""
    private(set) var standardError = ""
    private(set) var phase: Phase = .idle
    private(set) var outputTruncated = false
    private(set) var cliURL: URL?
    @ObservationIgnored private var hasLocatedCLI = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var tabID: UUID?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var manualRequestPending = false

    var isBusy: Bool { phase == .checking || phase == .running }

    func attach(tabID: UUID?) {
        guard self.tabID != tabID else { return }
        self.tabID = tabID
        cancel()
        clear()
    }

    func clear() {
        standardOutput = ""
        standardError = ""
        outputTruncated = false
        if !isBusy { phase = .idle }
    }

    func cancel() {
        generation &+= 1
        manualRequestPending = false
        task?.cancel()
        task = nil
        if isBusy { phase = .idle }
    }

    func resolveCLI(forceRefresh: Bool = false) -> URL? {
        if forceRefresh || !hasLocatedCLI || cliURL == nil {
            cliURL = MeierScriptRunner.locateCLI()
            hasLocatedCLI = true
        }
        return cliURL
    }

    /// Debounced follow-up to an edit: check syntax, then (opt-in) run.
    func scheduleAutomatic(source: @escaping @MainActor () -> String?, workingDirectory: URL?,
                           autoCheck: Bool, autoRun: Bool, replacesManualRequest: Bool = true) {
        guard autoCheck || autoRun, replacesManualRequest || !manualRequestPending else { return }
        start(debounce: true) { [weak self] in
            guard let self, let text = source() else { return }
            await self.perform(source: text, workingDirectory: workingDirectory, runAfterCheck: autoRun,
                               timeout: MeierScriptConsoleDefaults.automaticRunTimeout)
        }
    }

    func run(source: String, workingDirectory: URL?) {
        manualRequestPending = true
        start(debounce: false) { [weak self] in
            await self?.perform(source: source, workingDirectory: workingDirectory, runAfterCheck: true,
                                timeout: MeierScriptConsoleDefaults.manualRunTimeout)
        }
    }

    func checkSyntax(source: String) {
        manualRequestPending = true
        start(debounce: false) { [weak self] in
            await self?.perform(source: source, workingDirectory: nil, runAfterCheck: false,
                                timeout: MeierScriptConsoleDefaults.automaticRunTimeout)
        }
    }

    private func start(debounce: Bool, _ work: @escaping @MainActor () async -> Void) {
        if debounce { manualRequestPending = false }
        task?.cancel()
        generation &+= 1
        let current = generation
        task = Task { @MainActor [weak self] in
            if debounce {
                try? await Task.sleep(nanoseconds: MeierScriptConsoleDefaults.automaticDebounceNanoseconds)
            }
            guard !Task.isCancelled, self?.generation == current else { return }
            await work()
            if self?.generation == current { self?.manualRequestPending = false }
        }
    }

    private func perform(source: String, workingDirectory: URL?, runAfterCheck: Bool, timeout: TimeInterval) async {
        let current = generation
        guard let cli = resolveCLI() ?? resolveCLI(forceRefresh: true) else {
            phase = .cliMissing
            return
        }
        phase = .checking
        let check = await MeierScriptRunner.execute(source: source, mode: .syntaxCheck, cliURL: cli,
                                                    workingDirectory: nil, timeout: timeout)
        guard !Task.isCancelled, generation == current, !check.wasCancelled else { return }
        guard check.exitCode == 0, !check.timedOut else {
            standardError = check.standardError
            if !runAfterCheck { standardOutput = "" }
            phase = check.timedOut ? .timedOut : .syntaxError(MeierScriptLanguage.firstDiagnostic(in: check.standardError))
            return
        }
        guard runAfterCheck else {
            standardError = ""
            phase = .syntaxOK
            return
        }
        phase = .running
        let result = await MeierScriptRunner.execute(source: source, mode: .run, cliURL: cli,
                                                     workingDirectory: workingDirectory, timeout: timeout)
        guard !Task.isCancelled, generation == current, !result.wasCancelled else { return }
        standardOutput = result.standardOutput
        standardError = result.standardError
        outputTruncated = result.outputTruncated
        phase = result.timedOut ? .timedOut : .finished(exitCode: result.exitCode)
    }
}

/// Bottom panel for MeierScript documents: stdout and stderr in separate panes.
struct MeierScriptConsoleView: View {
    let tab: TabData
    let model: MeierScriptConsoleModel
    let onSelectLine: (Int) -> Void
    let onHide: () -> Void

    @AppStorage(MeierScriptConsoleDefaults.autoCheckKey) private var autoCheck = true
    @AppStorage(MeierScriptConsoleDefaults.autoRunKey) private var autoRun = false
    @AppStorage(MeierScriptConsoleDefaults.heightKey) private var storedHeight: Double = 200
    @State private var dragStartHeight: Double?

    private var workingDirectory: URL? { tab.fileURL?.deletingLastPathComponent() }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            toolbar
            Divider()
            HStack(spacing: 0) {
                MeierScriptOutputPane(title: "Output (stdout)", text: model.standardOutput, isError: false)
                Divider()
                MeierScriptOutputPane(title: "Errors (stderr)", text: model.standardError, isError: true)
            }
        }
        .frame(height: CGFloat(min(max(storedHeight, 120), 600)))
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("MeierScript Console"))
        .onAppear {
            model.attach(tabID: tab.id)
            // Opening the console for ⌘R must not replace that run.
            scheduleAutomatic(replacesManualRequest: false)
        }
        .onChange(of: tab.id) { _, newID in
            model.attach(tabID: newID)
            scheduleAutomatic()
        }
        .onChange(of: tab.contentRevision) { _, _ in scheduleAutomatic() }
        .onChange(of: autoRun) { _, enabled in if enabled { scheduleAutomatic() } }
        .onDisappear { model.cancel() }
    }

    private func currentSource() -> String? {
        tab.isLoadingContent ? nil : tab.document.string()
    }

    private func scheduleAutomatic(replacesManualRequest: Bool = true) {
        let tab = tab
        model.scheduleAutomatic(source: { tab.isLoadingContent ? nil : tab.document.string() },
                                workingDirectory: workingDirectory, autoCheck: autoCheck, autoRun: autoRun,
                                replacesManualRequest: replacesManualRequest)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 5)
            .overlay(Divider(), alignment: .top)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStartHeight ?? storedHeight
                        dragStartHeight = start
                        storedHeight = min(max(start - value.translation.height, 120), 600)
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text("MeierScript")
                .font(.system(size: 12, weight: .semibold))
            Button {
                if let source = currentSource() { model.run(source: source, workingDirectory: workingDirectory) }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .help(Text("Run the script with the meierscript CLI"))
            Button {
                if let source = currentSource() { model.checkSyntax(source: source) }
            } label: {
                Label("Check Syntax", systemImage: "checkmark.seal")
            }
            .help(Text("Parse the script without running it"))
            if model.isBusy {
                Button { model.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            Toggle("Auto-Check", isOn: $autoCheck)
                .toggleStyle(.checkbox)
                .help(Text("Check the syntax after each edit"))
            Toggle("Auto-Run", isOn: $autoRun)
                .toggleStyle(.checkbox)
                .help(Text("Run the script after each edit. Scripts can change files, preferences and system state."))
            Spacer(minLength: 8)
            statusView
            Button { model.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(Text("Clear Output"))
                .accessibilityLabel(Text("Clear Output"))
            Button(action: onHide) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help(Text("Hide MeierScript Console"))
                .accessibilityLabel(Text("Hide MeierScript Console"))
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .checking, .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(model.phase == .checking ? "Checking…" : "Running…")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        case .syntaxOK:
            Label("Syntax OK", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .syntaxError(let diagnostic):
            if let diagnostic {
                Button {
                    onSelectLine(diagnostic.line)
                } label: {
                    Label(String(format: NSLocalizedString("Syntax error in line %d", comment: "MeierScript status"), diagnostic.line),
                          systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .help(Text(verbatim: diagnostic.message))
            } else {
                Label("Syntax error", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        case .finished(let exitCode):
            HStack(spacing: 4) {
                Text(String(format: NSLocalizedString("Exit code %d", comment: "MeierScript status"), Int(exitCode)))
                if model.outputTruncated { Text("(output truncated)") }
            }
            .font(.system(size: 11))
            .foregroundStyle(exitCode == 0 ? Color.secondary : Color.red)
        case .timedOut:
            Label("Stopped after timeout", systemImage: "clock.badge.exclamationmark")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        case .cliMissing:
            Label("meierscript CLI not found. Install SidUI Editor or SidUI Viewer.", systemImage: "questionmark.app")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }
}

private struct MeierScriptOutputPane: View {
    let title: LocalizedStringKey
    let text: String
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            ScrollViewReader { proxy in
                ScrollView([.vertical, .horizontal]) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: text)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(isError ? Color.red : Color.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
                .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}
#endif

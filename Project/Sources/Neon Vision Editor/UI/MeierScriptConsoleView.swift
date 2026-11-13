#if os(macOS) && !APP_STORE_BUILD
import SwiftUI

enum MeierScriptConsoleDefaults {
    static let visibleKey = "MeierScriptConsoleVisible"
    /// Console visibility for interpreter languages (Python, shells, …). Off
    /// by default so their documents open without a panel; Run shows it.
    static let scriptVisibleKey = "ScriptConsoleVisible"
    static let autoCheckKey = "MeierScriptAutoCheckEnabled"
    static let autoRunKey = "MeierScriptAutoRunEnabled"
    static let heightKey = "MeierScriptConsoleHeight"
    /// Share of the console width the output pane takes; errors get the rest.
    static let outputFractionKey = "MeierScriptConsoleOutputFraction"
    static let paneFractionRange: ClosedRange<Double> = 0.15...0.85
    static let automaticDebounceNanoseconds: UInt64 = 600_000_000
    static let automaticRunTimeout: TimeInterval = 10
    static let manualRunTimeout: TimeInterval = 60
}

/// Language the run console serves: MeierScript through the SidUI CLI, or a
/// script language through an installed interpreter.
enum ScriptConsoleLanguage: Equatable {
    case meierScript
    case interpreter(ScriptInterpreter)

    init?(languageID: String) {
        if languageID.lowercased() == MeierScriptLanguage.identifier {
            self = .meierScript
        } else if let interpreter = ScriptInterpreter.forLanguage(languageID) {
            self = .interpreter(interpreter)
        } else {
            return nil
        }
    }

    var id: String {
        switch self {
        case .meierScript: return MeierScriptLanguage.identifier
        case .interpreter(let interpreter): return interpreter.languageID
        }
    }

    var displayName: String {
        switch self {
        case .meierScript: return MeierScriptLanguage.displayName
        case .interpreter(let interpreter): return interpreter.displayName
        }
    }

    var isMeierScript: Bool { self == .meierScript }

    var supportsSyntaxCheck: Bool {
        switch self {
        case .meierScript: return true
        case .interpreter(let interpreter): return interpreter.supportsSyntaxCheck
        }
    }

    var visibilityKey: String {
        isMeierScript ? MeierScriptConsoleDefaults.visibleKey : MeierScriptConsoleDefaults.scriptVisibleKey
    }

    var helpSectionKey: String {
        isMeierScript ? MeierScriptHelp.sectionKey : ScriptRunHelp.sectionKey
    }

    func firstDiagnostic(in output: String) -> MeierScriptLanguage.Diagnostic? {
        switch self {
        case .meierScript: return MeierScriptLanguage.firstDiagnostic(in: output)
        case .interpreter(let interpreter): return interpreter.firstDiagnostic(in: output)
        }
    }
}

/// Per-window state of the run console. One script runs at a time; a
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
    private(set) var language: ScriptConsoleLanguage = .meierScript
    @ObservationIgnored private var hasLocatedCLI = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var tabID: UUID?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var manualRequestPending = false

    var isBusy: Bool { phase == .checking || phase == .running }

    func attach(tabID: UUID?, language: ScriptConsoleLanguage) {
        guard self.tabID != tabID || self.language != language else { return }
        self.tabID = tabID
        self.language = language
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
                               isManual: false, timeout: MeierScriptConsoleDefaults.automaticRunTimeout)
        }
    }

    func run(source: String, workingDirectory: URL?) {
        manualRequestPending = true
        start(debounce: false) { [weak self] in
            await self?.perform(source: source, workingDirectory: workingDirectory, runAfterCheck: true,
                                isManual: true, timeout: MeierScriptConsoleDefaults.manualRunTimeout)
        }
    }

    func checkSyntax(source: String, workingDirectory: URL? = nil) {
        manualRequestPending = true
        start(debounce: false) { [weak self] in
            await self?.perform(source: source, workingDirectory: workingDirectory, runAfterCheck: false,
                                isManual: true, timeout: MeierScriptConsoleDefaults.automaticRunTimeout)
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

    /// `workingDirectory` is where a run starts; syntax checks only use it to
    /// find a project interpreter such as a Python `.venv`.
    private func perform(source: String, workingDirectory: URL?, runAfterCheck: Bool, isManual: Bool,
                         timeout: TimeInterval) async {
        let current = generation
        let language = language
        let runTool: URL?
        let checkTool: URL?
        switch language {
        case .meierScript:
            let cli = resolveCLI() ?? resolveCLI(forceRefresh: true)
            runTool = cli
            checkTool = cli
        case .interpreter(let interpreter):
            runTool = runAfterCheck ? interpreter.locate(interpreter.run, workingDirectory: workingDirectory) : nil
            checkTool = interpreter.syntaxCheck.flatMap { interpreter.locate($0, workingDirectory: workingDirectory) }
        }
        guard (runAfterCheck ? runTool : checkTool) != nil else {
            phase = .cliMissing
            return
        }
        // A language without a checker (or without its checker installed)
        // runs directly; runtime errors still appear in the error pane.
        if let checkTool {
            phase = .checking
            let check = await execute(source: source, mode: .syntaxCheck, language: language, tool: checkTool,
                                      workingDirectory: nil, timeout: timeout)
            guard !Task.isCancelled, generation == current, !check.wasCancelled else { return }
            guard check.exitCode == 0, !check.timedOut else {
                standardError = check.standardError
                // Auto-Run keeps the last good output while you type; a manual
                // request must not show output from an earlier run.
                if !runAfterCheck || isManual { standardOutput = "" }
                phase = check.timedOut ? .timedOut : .syntaxError(language.firstDiagnostic(in: check.standardError))
                return
            }
        }
        guard runAfterCheck, let runTool else {
            standardError = ""
            phase = .syntaxOK
            return
        }
        phase = .running
        let result = await execute(source: source, mode: .run, language: language, tool: runTool,
                                   workingDirectory: workingDirectory, timeout: timeout)
        guard !Task.isCancelled, generation == current, !result.wasCancelled else { return }
        standardOutput = result.standardOutput
        standardError = result.standardError
        outputTruncated = result.outputTruncated
        phase = result.timedOut ? .timedOut : .finished(exitCode: result.exitCode)
    }

    private func execute(source: String, mode: MeierScriptRunner.Mode, language: ScriptConsoleLanguage, tool: URL,
                         workingDirectory: URL?, timeout: TimeInterval) async -> MeierScriptRunner.Result {
        switch language {
        case .meierScript:
            return await MeierScriptRunner.execute(source: source, mode: mode, cliURL: tool,
                                                   workingDirectory: workingDirectory, timeout: timeout)
        case .interpreter(let interpreter):
            return await interpreter.execute(source: source, mode: mode, executableURL: tool,
                                             workingDirectory: workingDirectory, timeout: timeout)
        }
    }
}

/// Bottom panel for MeierScript and script documents: stdout and stderr in
/// separate panes.
/// Window styling the console follows so it reads as part of the editor:
/// the editor surface (translucent, opaque canvas or solid), theme colors and
/// the editor font.
struct MeierScriptConsoleAppearance {
    var background: AnyShapeStyle
    var text: Color
    var error: Color
    var fontName: String
    var fontSize: CGFloat

    var outputFont: Font {
        let size = max(9, fontSize - 1)
        return fontName.isEmpty ? .system(size: size, design: .monospaced) : .custom(fontName, size: size)
    }
}

struct MeierScriptConsoleView: View {
    let tab: TabData
    let language: ScriptConsoleLanguage
    let model: MeierScriptConsoleModel
    let onSelectLine: (Int) -> Void
    let onHide: () -> Void
    let onShowHelp: () -> Void
    let appearance: MeierScriptConsoleAppearance

    @AppStorage(MeierScriptConsoleDefaults.autoCheckKey) private var autoCheck = true
    @AppStorage(MeierScriptConsoleDefaults.autoRunKey) private var autoRun = false
    @AppStorage(MeierScriptConsoleDefaults.heightKey) private var storedHeight: Double = 200
    @AppStorage(MeierScriptConsoleDefaults.outputFractionKey) private var outputFraction: Double = 0.5
    @State private var dragStartHeight: Double?
    @State private var dragStartFraction: Double?

    private var workingDirectory: URL? { tab.fileURL?.deletingLastPathComponent() }

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            toolbar
            Divider()
            GeometryReader { proxy in
                let fraction = min(max(outputFraction, MeierScriptConsoleDefaults.paneFractionRange.lowerBound),
                                   MeierScriptConsoleDefaults.paneFractionRange.upperBound)
                HStack(spacing: 0) {
                    MeierScriptOutputPane(title: "Output (stdout)", text: model.standardOutput,
                                          font: appearance.outputFont, color: appearance.text)
                        .frame(width: max(0, proxy.size.width * fraction))
                    paneSplitHandle(totalWidth: proxy.size.width)
                    MeierScriptOutputPane(title: "Errors (stderr)", text: model.standardError,
                                          font: appearance.outputFont, color: appearance.error)
                }
            }
        }
        .frame(height: CGFloat(min(max(storedHeight, 120), 600)))
        .background(appearance.background)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(language.isMeierScript ? NSLocalizedString("MeierScript Console", comment: "")
                                 : String(format: NSLocalizedString("%@ Console", comment: "Run console accessibility label"),
                                          language.displayName)))
        .onAppear {
            model.attach(tabID: tab.id, language: language)
            // Opening the console for ⌘R must not replace that run, and
            // showing a document never runs it: Auto-Run reacts to edits only.
            scheduleAutomatic(allowsRun: false, replacesManualRequest: false)
        }
        .onChange(of: tab.id) { _, newID in
            model.attach(tabID: newID, language: language)
            scheduleAutomatic(allowsRun: false)
        }
        .onChange(of: language) { _, newLanguage in
            model.attach(tabID: tab.id, language: newLanguage)
            scheduleAutomatic(allowsRun: false)
        }
        // Loading or reloading a file also bumps the revision but leaves the
        // tab clean, so only unsaved edits trigger an automatic run.
        .onChange(of: tab.contentRevision) { _, _ in scheduleAutomatic(allowsRun: tab.isDirty) }
        .onChange(of: autoRun) { _, enabled in if enabled { scheduleAutomatic(allowsRun: true) } }
        .onDisappear { model.cancel() }
    }

    private func currentSource() -> String? {
        tab.isLoadingContent ? nil : tab.document.string()
    }

    private func scheduleAutomatic(allowsRun: Bool, replacesManualRequest: Bool = true) {
        let tab = tab
        model.scheduleAutomatic(source: { tab.isLoadingContent ? nil : tab.document.string() },
                                workingDirectory: workingDirectory,
                                autoCheck: autoCheck && language.supportsSyntaxCheck,
                                autoRun: allowsRun && autoRun,
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

    /// Divider between the output and error panes; dragging it resizes both.
    private func paneSplitHandle(totalWidth: CGFloat) -> some View {
        Divider()
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard totalWidth > 0 else { return }
                                let start = dragStartFraction ?? outputFraction
                                dragStartFraction = start
                                outputFraction = min(max(start + Double(value.translation.width / totalWidth),
                                                         MeierScriptConsoleDefaults.paneFractionRange.lowerBound),
                                                     MeierScriptConsoleDefaults.paneFractionRange.upperBound)
                            }
                            .onEnded { _ in dragStartFraction = nil }
                    )
                    // Double-click splits the panes evenly again.
                    .onTapGesture(count: 2) { outputFraction = 0.5 }
            )
            .accessibilityHidden(true)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(verbatim: language.displayName)
                .font(.system(size: 12, weight: .semibold))
            Button {
                if let source = currentSource() { model.run(source: source, workingDirectory: workingDirectory) }
            } label: {
                Label("Run", systemImage: "play.fill")
            }
            .help(language.isMeierScript ? Text("Run the script with the meierscript CLI")
                  : Text("Run the script as it is in the editor"))
            if language.supportsSyntaxCheck {
                Button {
                    if let source = currentSource() { model.checkSyntax(source: source, workingDirectory: workingDirectory) }
                } label: {
                    Label("Check Syntax", systemImage: "checkmark.seal")
                }
                .help(Text("Parse the script without running it"))
            }
            if model.isBusy {
                Button { model.cancel() } label: { Label("Stop", systemImage: "stop.fill") }
            }
            if language.supportsSyntaxCheck {
                Toggle("Auto-Check", isOn: $autoCheck)
                    .toggleStyle(.checkbox)
                    .help(Text("Check the syntax after each edit"))
            }
            Toggle("Auto-Run", isOn: $autoRun)
                .toggleStyle(.checkbox)
                .help(Text("Run the script after each edit. Scripts can change files, preferences and system state."))
            Spacer(minLength: 8)
            statusView
            Button(action: onShowHelp) { Image(systemName: "questionmark.circle") }
                .buttonStyle(.borderless)
                .help(language.isMeierScript ? Text("MeierScript Help") : Text("Run Scripts Help"))
                .accessibilityLabel(language.isMeierScript ? Text("MeierScript Help") : Text("Run Scripts Help"))
            Button { model.clear() } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help(Text("Clear Output"))
                .accessibilityLabel(Text("Clear Output"))
            Button(action: onHide) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help(language.isMeierScript ? Text("Hide MeierScript Console") : Text("Hide Console"))
                .accessibilityLabel(language.isMeierScript ? Text("Hide MeierScript Console") : Text("Hide Console"))
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
            Group {
                switch language {
                case .meierScript:
                    Label("meierscript CLI not found. Install SidUI Editor or SidUI Viewer.", systemImage: "questionmark.app")
                case .interpreter(let interpreter):
                    Label(String(format: NSLocalizedString("%@ not found. Install it, for example with Homebrew.",
                                                           comment: "Run console: interpreter missing"),
                                 interpreter.run.executableNames.first ?? interpreter.displayName),
                          systemImage: "questionmark.app")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.orange)
            .lineLimit(1)
        }
    }
}

private struct MeierScriptOutputPane: View {
    let title: LocalizedStringKey
    let text: String
    let font: Font
    let color: Color

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
                            .font(font)
                            .foregroundStyle(color)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: false)
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
                // .bottom centers horizontally, which hid the start of long
                // lines on every update; keep the leading edge in view.
                .onChange(of: text) { _, _ in proxy.scrollTo("end", anchor: .bottomLeading) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }
}
#endif

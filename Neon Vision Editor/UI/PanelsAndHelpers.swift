import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif



/// MARK: - Types

enum NeonUIStyle {
    static let accentBlue = Color(red: 0.17, green: 0.49, blue: 0.98)
    static let accentBlueSoft = Color(red: 0.44, green: 0.72, blue: 0.99)
    static let accentBlueStrong = Color(red: 0.05, green: 0.44, blue: 0.98)

    static func surfaceFill(for scheme: ColorScheme) -> LinearGradient {
        let top = scheme == .dark
            ? Color(red: 0.09, green: 0.14, blue: 0.23).opacity(0.82)
            : Color(red: 0.94, green: 0.97, blue: 1.00).opacity(0.94)
        let bottom = scheme == .dark
            ? Color(red: 0.06, green: 0.10, blue: 0.18).opacity(0.88)
            : Color(red: 0.88, green: 0.94, blue: 1.00).opacity(0.96)
        return LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? accentBlueSoft.opacity(0.34)
            : accentBlue.opacity(0.22)
    }

    static func searchMatchFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? accentBlueSoft.opacity(0.32)
            : accentBlue.opacity(0.18)
    }

    static func selectedRowFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? accentBlueSoft.opacity(0.20)
            : accentBlue.opacity(0.10)
    }
}

private struct SearchPanelSurfaceModifier: ViewModifier {
    @AppStorage("EnableTranslucentWindow") private var enableTranslucentWindow: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(surfaceBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(enableTranslucentWindow ? 0.12 : 0.08), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private var surfaceBackground: some View {
        let fallback = colorScheme == .dark ? Color.black.opacity(0.16) : Color.white.opacity(0.78)
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(enableTranslucentWindow ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(fallback))
    }
}

private extension View {
    func subtleSearchPanelSurface() -> some View {
        modifier(SearchPanelSurfaceModifier())
    }
}

private struct SearchPanelSectionCardModifier: ViewModifier {
    @AppStorage("EnableTranslucentWindow") private var enableTranslucentWindow: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(sectionBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(enableTranslucentWindow ? 0.1 : 0.07), lineWidth: 0.8)
            )
    }

    @ViewBuilder
    private var sectionBackground: some View {
        let fallback = colorScheme == .dark
            ? Color.black.opacity(0.11)
            : Color.white.opacity(0.58)
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(enableTranslucentWindow ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(fallback))
    }
}

private extension View {
    func subtleSearchSectionCard() -> some View {
        modifier(SearchPanelSectionCardModifier())
    }
}

private struct SearchPanelActionButtonModifier: ViewModifier {
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, prominent ? 14 : 12)
            .padding(.vertical, 8)
            .background(backgroundShape)
            .overlay(strokeShape)
            .clipShape(Capsule())
    }

    private var foregroundColor: Color {
        if prominent {
            return .white.opacity(isEnabled ? 1 : 0.92)
        }
        if isEnabled {
            return colorScheme == .dark ? .white.opacity(0.96) : .primary
        }
        return colorScheme == .dark ? Color.white.opacity(0.56) : Color.primary.opacity(0.45)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        Capsule()
            .fill(backgroundColor)
    }

    @ViewBuilder
    private var strokeShape: some View {
        Capsule()
            .stroke(strokeColor, lineWidth: 0.8)
    }

    private var backgroundColor: Color {
        if prominent {
            return isEnabled
                ? NeonUIStyle.accentBlue
                : NeonUIStyle.accentBlue.opacity(colorScheme == .dark ? 0.55 : 0.40)
        }
        if colorScheme == .dark {
            return isEnabled
                ? Color.white.opacity(0.12)
                : Color.white.opacity(0.08)
        }
        return isEnabled
            ? Color.black.opacity(0.05)
            : Color.black.opacity(0.03)
    }

    private var strokeColor: Color {
        if prominent {
            return isEnabled ? Color.white.opacity(0.10) : Color.white.opacity(0.08)
        }
        return colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.06)
    }
}

private extension View {
    func searchPanelActionButton(prominent: Bool = false) -> some View {
        modifier(SearchPanelActionButtonModifier(prominent: prominent))
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .text, .sourceCode] }

    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let decoded = String(data: data, encoding: .utf8) {
            text = decoded
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = text.data(using: .utf8) ?? Data()
        return FileWrapper(regularFileWithContents: data)
    }
}

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct APISupportSettingsView: View {
    @Binding var grokAPIToken: String
    @Binding var openAIAPIToken: String
    @Binding var geminiAPIToken: String
    @Binding var anthropicAPIToken: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI Provider API Keys").font(.headline)
            Group {
                LabeledContent("Grok") {
                    SecureField("sk-…", text: $grokAPIToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: grokAPIToken) { _, new in
                            SecureTokenStore.setToken(new, for: .grok)
                        }
                }
                LabeledContent("OpenAI") {
                    SecureField("sk-…", text: $openAIAPIToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: openAIAPIToken) { _, new in
                            SecureTokenStore.setToken(new, for: .openAI)
                        }
                }
                LabeledContent("Gemini") {
                    SecureField("AIza…", text: $geminiAPIToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: geminiAPIToken) { _, new in
                            SecureTokenStore.setToken(new, for: .gemini)
                        }
                }
                LabeledContent("Anthropic") {
                    SecureField("sk-ant-…", text: $anthropicAPIToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: anthropicAPIToken) { _, new in
                            SecureTokenStore.setToken(new, for: .anthropic)
                        }
                }
            }
            .labelStyle(.titleAndIcon)

            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding(20)
        .frame(minWidth: 460)
    }
}

struct FindReplacePanel: View {
    @Binding var findQuery: String
    @Binding var replaceQuery: String
    @Binding var useRegex: Bool
    @Binding var caseSensitive: Bool
    @Binding var matchCount: Int
    @Binding var statusMessage: String
    var onPreviewChanged: () -> Void
    var onFindNext: () -> Void
    var onJumpToMatch: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onClose: () -> Void
    @FocusState private var findFieldFocused: Bool

    private var usesCompactPhoneLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    private var usesPadLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    private var matchSummaryText: String {
        matchCount == 1
            ? String.localizedStringWithFormat(NSLocalizedString("%lld match", comment: ""), Int64(matchCount))
            : String.localizedStringWithFormat(NSLocalizedString("%lld matches", comment: ""), Int64(matchCount))
    }

    @ViewBuilder
    private var centeredTitleHeader: some View {
        ZStack {
            Text(NSLocalizedString("Find & Replace", comment: ""))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)

            if usesCompactPhoneLayout {
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Close", comment: "")) { onClose() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .searchPanelActionButton()
                }
            }
        }
    }

    @ViewBuilder
    private var phoneFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            phoneFieldRow(
                title: NSLocalizedString("Find", comment: ""),
                placeholder: NSLocalizedString("Search text", comment: ""),
                text: $findQuery,
                isFocused: true
            )
            phoneFieldRow(
                title: NSLocalizedString("Replace", comment: ""),
                placeholder: NSLocalizedString("Replacement", comment: ""),
                text: $replaceQuery
            )
        }
        .padding(14)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private func phoneFieldRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isFocused: Bool = false,
        labelWidth: CGFloat = 76
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .frame(width: labelWidth, alignment: .leading)

            if isFocused {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focused($findFieldFocused)
                    .onSubmit { onFindNext() }
            } else {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var padFieldsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            phoneFieldRow(
                title: NSLocalizedString("Find", comment: ""),
                placeholder: NSLocalizedString("Search text", comment: ""),
                text: $findQuery,
                isFocused: true,
                labelWidth: 88
            )
            phoneFieldRow(
                title: NSLocalizedString("Replace", comment: ""),
                placeholder: NSLocalizedString("Replacement", comment: ""),
                text: $replaceQuery,
                labelWidth: 88
            )
        }
        .padding(18)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var phoneOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(NSLocalizedString("Use Regex", comment: ""), isOn: $useRegex)
            Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)

            VStack(alignment: .leading, spacing: 4) {
                Text(String.localizedStringWithFormat(NSLocalizedString("Matches: %@", comment: ""), matchSummaryText))
                    .font(.caption.weight(.medium))
                    .foregroundColor(matchCount > 0 ? .primary : Color.secondary)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var padOptionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(NSLocalizedString("Use Regex", comment: ""), isOn: $useRegex)
            Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)

            VStack(alignment: .leading, spacing: 4) {
                Text(String.localizedStringWithFormat(NSLocalizedString("Matches: %@", comment: ""), matchSummaryText))
                    .font(.caption.weight(.medium))
                    .foregroundColor(matchCount > 0 ? .primary : Color.secondary)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(18)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var padActionSection: some View {
        HStack(spacing: 10) {
            Button(NSLocalizedString("Find Next", comment: "")) { onFindNext() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton(prominent: true)

            Button(NSLocalizedString("Jump to Match", comment: "")) {
                onJumpToMatch()
                onClose()
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .searchPanelActionButton()
            .disabled(findQuery.isEmpty || matchCount == 0)

            Button(NSLocalizedString("Replace", comment: "")) { onReplace() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton()
                .disabled(findQuery.isEmpty)

            Button(NSLocalizedString("Replace All", comment: "")) { onReplaceAll() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton()
                .disabled(findQuery.isEmpty)

            Button(NSLocalizedString("Close", comment: "")) { onClose() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton()
        }
    }

    @ViewBuilder
    private var phoneActionSection: some View {
        HStack(spacing: 6) {
            compactPhoneActionButton(
                NSLocalizedString("Find Next", comment: ""),
                prominent: true,
                disabled: false
            ) { onFindNext() }

            compactPhoneActionButton(
                NSLocalizedString("Jump to Match", comment: ""),
                disabled: findQuery.isEmpty || matchCount == 0
            ) {
                onJumpToMatch()
                onClose()
            }

            compactPhoneActionButton(
                NSLocalizedString("Replace", comment: ""),
                disabled: findQuery.isEmpty
            ) { onReplace() }

            compactPhoneActionButton(
                NSLocalizedString("Replace All", comment: ""),
                disabled: findQuery.isEmpty
            ) { onReplaceAll() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func compactPhoneActionButton(
        _ title: String,
        prominent: Bool = false,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .disabled(disabled)
                .searchPanelActionButton(prominent: true)
        } else {
            Button(title, action: action)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .frame(maxWidth: .infinity)
                .disabled(disabled)
                .searchPanelActionButton()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesCompactPhoneLayout {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 18)

                    VStack(alignment: .leading, spacing: 16) {
                        centeredTitleHeader
                        phoneFieldsSection
                        phoneOptionsSection
                        phoneActionSection
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 424, alignment: .top)
            } else if usesPadLayout {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 22)

                    VStack(alignment: .leading, spacing: 18) {
                        centeredTitleHeader
                        padFieldsSection
                        padOptionsSection
                        padActionSection
                    }

                    Spacer(minLength: 18)
                }
                .frame(maxWidth: .infinity, minHeight: 540, alignment: .top)
            } else {
                centeredTitleHeader
                LabeledContent(NSLocalizedString("Find", comment: "")) {
                    TextField(NSLocalizedString("Search text", comment: ""), text: $findQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($findFieldFocused)
                        .onSubmit { onFindNext() }
                }
                LabeledContent(NSLocalizedString("Replace", comment: "")) {
                    TextField(NSLocalizedString("Replacement", comment: ""), text: $replaceQuery)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle(NSLocalizedString("Use Regex", comment: ""), isOn: $useRegex)
                Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)
                Text(String.localizedStringWithFormat(NSLocalizedString("Matches: %@", comment: ""), matchSummaryText))
                    .font(.caption.weight(.medium))
                    .foregroundColor(matchCount > 0 ? .primary : Color.secondary)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button(NSLocalizedString("Find Next", comment: "")) { onFindNext() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.semibold))
                        .searchPanelActionButton(prominent: true)
                    Button(NSLocalizedString("Jump to Match", comment: "")) {
                        onJumpToMatch()
                        onClose()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .searchPanelActionButton()
                    .disabled(findQuery.isEmpty || matchCount == 0)
                    Button(NSLocalizedString("Replace", comment: "")) { onReplace() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                        .disabled(findQuery.isEmpty)
                    Button(NSLocalizedString("Replace All", comment: "")) { onReplaceAll() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                        .disabled(findQuery.isEmpty)
                    Spacer()
                    Button(NSLocalizedString("Close", comment: "")) { onClose() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                }
            }
        }
        .padding(.horizontal, usesPadLayout ? 8 : 16)
        .padding(.vertical, 16)
#if os(iOS)
        .frame(maxWidth: usesPadLayout ? 460 : .infinity)
#else
        .frame(minWidth: 560, idealWidth: 620)
#endif
        .subtleSearchPanelSurface()
        .onAppear {
            findFieldFocused = true
            onPreviewChanged()
        }
        .onChange(of: findQuery) { _, _ in onPreviewChanged() }
        .onChange(of: useRegex) { _, _ in onPreviewChanged() }
        .onChange(of: caseSensitive) { _, _ in onPreviewChanged() }
    }
}

#if os(macOS)
struct FindReplaceWindowPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    @Binding var findQuery: String
    @Binding var replaceQuery: String
    @Binding var useRegex: Bool
    @Binding var caseSensitive: Bool
    @Binding var matchCount: Int
    @Binding var statusMessage: String
    let onPreviewChanged: () -> Void
    let onFindNext: () -> Void
    let onJumpToMatch: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    final class Coordinator: NSObject, NSWindowDelegate {
        var parent: FindReplaceWindowPresenter
        weak var hostWindow: NSWindow?
        var window: NSPanel?
        var hostingController: NSHostingController<FindReplacePanel>?

        init(parent: FindReplaceWindowPresenter) {
            self.parent = parent
        }

        func panelContent() -> FindReplacePanel {
            FindReplacePanel(
                findQuery: parent.$findQuery,
                replaceQuery: parent.$replaceQuery,
                useRegex: parent.$useRegex,
                caseSensitive: parent.$caseSensitive,
                matchCount: parent.$matchCount,
                statusMessage: parent.$statusMessage,
                onPreviewChanged: parent.onPreviewChanged,
                onFindNext: parent.onFindNext,
                onJumpToMatch: parent.onJumpToMatch,
                onReplace: parent.onReplace,
                onReplaceAll: parent.onReplaceAll,
                onClose: parent.onClose
            )
        }

        func presentIfNeeded() {
            if let window, let hostingController {
                hostingController.rootView = panelContent()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let controller = NSHostingController(rootView: panelContent())
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 300),
                styleMask: [.titled, .fullSizeContentView, .utilityWindow],
                backing: .buffered,
                defer: false
            )
            panel.contentViewController = controller
            panel.title = NSLocalizedString("Find & Replace", comment: "")
            panel.isReleasedWhenClosed = false
            panel.tabbingMode = .disallowed
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.delegate = self
            panel.minSize = NSSize(width: 620, height: 300)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true

            if let hostWindow {
                let hostFrame = hostWindow.frame
                let size = panel.frame.size
                let origin = NSPoint(
                    x: hostFrame.midX - (size.width / 2),
                    y: hostFrame.midY - (size.height / 2)
                )
                panel.setFrameOrigin(origin)
            } else {
                panel.center()
            }

            self.window = panel
            self.hostingController = controller
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func dismissIfNeeded() {
            guard let window else { return }
            window.orderOut(nil)
            window.close()
            self.window = nil
            self.hostingController = nil
        }

        func windowWillClose(_ notification: Notification) {
            self.window = nil
            self.hostingController = nil
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.hostWindow = view.window
            if isPresented {
                context.coordinator.presentIfNeeded()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostWindow = nsView.window
        if isPresented {
            context.coordinator.presentIfNeeded()
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }
}
#endif

struct QuickFileSwitcherPanel: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let isPinned: Bool
        let canTogglePin: Bool
    }

    @Binding var query: String
    let items: [Item]
    let statusMessage: String
    let onSelect: (Item) -> Void
    let onTogglePin: (Item) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var queryFieldFocused: Bool
    @State private var selectedItemID: Item.ID?

    private var selectedItem: Item? {
        guard let selectedItemID else { return items.first }
        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    private func selectPrimaryItem() {
        guard let item = selectedItem else { return }
        onSelect(item)
        dismiss()
    }

    private func syncSelectionToVisibleItems() {
        guard let selectedItemID,
              items.contains(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        syncSelectionToVisibleItems()
        let currentIndex = items.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        selectedItemID = items[nextIndex].id
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func highlightedText(_ text: String, useSecondaryTone: Bool) -> Text {
        let searchTerm = normalizedQuery
        let baseColor: Color = useSecondaryTone
            ? Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.72)
            : .primary
        guard !searchTerm.isEmpty else { return Text(text).foregroundColor(baseColor) }

        let compareOptions: String.CompareOptions = [.caseInsensitive]
        var rendered = Text("")
        var remaining = text[...]

        while let range = remaining.range(of: searchTerm, options: compareOptions) {
            let prefix = String(remaining[..<range.lowerBound])
            let match = String(remaining[range])
            if !prefix.isEmpty {
                rendered = rendered + Text(prefix).foregroundColor(baseColor)
            }
            rendered = rendered + Text(match)
                .foregroundColor(NeonUIStyle.accentBlueStrong)
                .fontWeight(.semibold)
                .underline()
            remaining = remaining[range.upperBound...]
        }

        if !remaining.isEmpty {
            rendered = rendered + Text(String(remaining)).foregroundColor(baseColor)
        }
        return rendered
    }

    @ViewBuilder
    private func applyMoveCommand<Content: View>(to content: Content) -> some View {
#if os(macOS)
        content.onMoveCommand { direction in
            switch direction {
            case .down:
                moveSelection(by: 1)
            case .up:
                moveSelection(by: -1)
            default:
                break
            }
        }
#else
        content
#endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            applyMoveCommand(to:
                VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Command Palette", comment: ""))
                    .font(.headline)
                TextField(NSLocalizedString("Search commands, files, and tabs", comment: ""), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { selectPrimaryItem() }
                    .accessibilityLabel(NSLocalizedString("Command Palette Search", comment: ""))
                    .accessibilityHint(NSLocalizedString("Type to search commands, files, and tabs. Use Up and Down Arrow to move through results.", comment: ""))
                    .focused($queryFieldFocused)

                List(items) { item in
                    HStack(spacing: 10) {
                        Button {
                            selectedItemID = item.id
                            onSelect(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                highlightedText(item.title, useSecondaryTone: false)
                                    .lineLimit(1)
                                highlightedText(item.subtitle, useSecondaryTone: true)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.subtitle)
                        .accessibilityHint(NSLocalizedString("Opens the selected item", comment: ""))

                        if item.canTogglePin {
                            Button {
                                selectedItemID = item.id
                                onTogglePin(item)
                            } label: {
                                Image(systemName: item.isPinned ? "star.fill" : "star")
                                    .foregroundStyle(item.isPinned ? Color.yellow : .secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.isPinned ? NSLocalizedString("Unpin recent file", comment: "") : NSLocalizedString("Pin recent file", comment: ""))
                            .accessibilityHint(NSLocalizedString("Keeps this file near the top of recent results", comment: ""))
                        }
                    }
                    .id(item.id)
                    .contentShape(Rectangle())
                    .listRowBackground(
                        selectedItemID == item.id
                        ? NeonUIStyle.selectedRowFill(for: colorScheme)
                        : Color.clear
                    )
                    .onTapGesture {
                        selectedItemID = item.id
                    }
                }
                .listStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Command Palette Results", comment: ""))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String.localizedStringWithFormat(NSLocalizedString("%lld results", comment: ""), Int64(items.count)))
                        if !statusMessage.isEmpty {
                            Text(statusMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Close", comment: "")) { dismiss() }
                }
            }
#if os(iOS)
            .background(
                DirectionalKeyCommandBridge(
                    onMoveUp: { moveSelection(by: -1) },
                    onMoveDown: { moveSelection(by: 1) }
                )
                .frame(width: 0, height: 0)
            )
#endif
            .padding(16)
            .frame(minWidth: 520, minHeight: 380)
            .onAppear {
                queryFieldFocused = true
                syncSelectionToVisibleItems()
            }
            .onChange(of: items.map(\.id)) { _, _ in
                syncSelectionToVisibleItems()
            }
            .onChange(of: selectedItemID) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue, anchor: .center)
            }
            )
        }
    }
}

struct DocumentSymbolItem: Identifiable, Hashable {
    let id: String
    let title: String
    let line: Int?
}

enum DocumentSymbolNavigator {
    static func symbols(content: String, language: String) -> [DocumentSymbolItem] {
        guard !content.isEmpty else {
            return [DocumentSymbolItem(id: "empty", title: "No content available", line: nil)]
        }
        if (content as NSString).length >= 400_000 {
            return [DocumentSymbolItem(id: "large", title: "Large file detected: symbols disabled for performance", line: nil)]
        }

        let lines = content.components(separatedBy: .newlines)
        let lowerLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let symbols: [DocumentSymbolItem]

        switch lowerLanguage {
        case "swift":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("enum ") {
                    return DocumentSymbolItem(id: "swift-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "python":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") {
                    return DocumentSymbolItem(id: "python-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "javascript":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") {
                    return DocumentSymbolItem(id: "js-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "java":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("class ") || (trimmed.contains(" void ") || (trimmed.contains(" public ") && trimmed.contains("(") && trimmed.contains(")"))) {
                    return DocumentSymbolItem(id: "java-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "kotlin":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("class ") || trimmed.hasPrefix("object ") || trimmed.hasPrefix("fun ") {
                    return DocumentSymbolItem(id: "kotlin-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "go":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("func ") || trimmed.hasPrefix("type ") {
                    return DocumentSymbolItem(id: "go-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "ruby":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("def ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("module ") {
                    return DocumentSymbolItem(id: "ruby-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "rust":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("fn ") || trimmed.hasPrefix("struct ") || trimmed.hasPrefix("enum ") || trimmed.hasPrefix("impl ") {
                    return DocumentSymbolItem(id: "rust-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "typescript":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") || trimmed.hasPrefix("interface ") || trimmed.hasPrefix("type ") {
                    return DocumentSymbolItem(id: "ts-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "php":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasPrefix("class ") {
                    return DocumentSymbolItem(id: "php-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "objective-c":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("@interface") || trimmed.hasPrefix("@implementation") || trimmed.hasPrefix("- (") || trimmed.hasPrefix("+ (") {
                    return DocumentSymbolItem(id: "objc-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "c", "cpp":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("struct ") || trimmed.hasPrefix("class ") || (trimmed.contains("(") && trimmed.hasSuffix("{")) {
                    return DocumentSymbolItem(id: "c-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "bash", "zsh":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("function ") || trimmed.hasSuffix("() {") {
                    return DocumentSymbolItem(id: "sh-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "powershell":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("function ") {
                    return DocumentSymbolItem(id: "ps-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "markdown", "rst", "tex":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let isMarkdownHeader = trimmed.hasPrefix("#")
                let isRSTHeader = index + 1 < lines.count && !trimmed.isEmpty && Set(lines[index + 1]).isSubset(of: Set(["=", "-", "~", "^", "\""]))
                let isTeXSection = trimmed.hasPrefix("\\section") || trimmed.hasPrefix("\\subsection") || trimmed.hasPrefix("\\chapter")
                if isMarkdownHeader || isRSTHeader || isTeXSection {
                    return DocumentSymbolItem(id: "markup-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        case "csharp":
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("class ") || trimmed.hasPrefix("interface ") || trimmed.hasPrefix("struct ") || trimmed.contains(" void ") {
                    return DocumentSymbolItem(id: "cs-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        default:
            symbols = lines.enumerated().compactMap { index, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    return DocumentSymbolItem(id: "default-\(index)", title: "\(trimmed) (Line \(index + 1))", line: index + 1)
                }
                return nil
            }
        }

        return symbols.isEmpty ? [DocumentSymbolItem(id: "none", title: "No symbols found", line: nil)] : symbols
    }
}

struct GoToLinePanel: View {
    @Binding var lineInput: String
    let currentLineCount: Int
    let onGoToLine: (Int) -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var lineFieldFocused: Bool
    @State private var validationMessage: String = ""

    private func submit() {
        let trimmed = lineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line = Int(trimmed), line > 0 else {
            validationMessage = NSLocalizedString("Enter a line number greater than 0.", comment: "Go to Line validation")
            return
        }
        validationMessage = ""
        onGoToLine(line)
        dismiss()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("Go to Line", comment: "Go to Line panel title"))
                .font(.headline)

            TextField(NSLocalizedString("Line number", comment: "Go to Line input placeholder"), text: $lineInput)
#if os(iOS)
                .keyboardType(.numberPad)
#endif
                .textFieldStyle(.roundedBorder)
                .focused($lineFieldFocused)
                .onSubmit { submit() }
                .accessibilityLabel(NSLocalizedString("Line Number", comment: "Go to Line accessibility label"))
                .accessibilityHint(NSLocalizedString("Enter a line number and jump to that location in the current document.", comment: "Go to Line accessibility hint"))

            Text(String.localizedStringWithFormat(NSLocalizedString("Current document has %lld lines.", comment: "Go to Line helper"), Int64(max(1, currentLineCount))))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !validationMessage.isEmpty {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button(NSLocalizedString("Go", comment: "Go to Line submit button")) {
                    submit()
                }
                .buttonStyle(.plain)
                .searchPanelActionButton(prominent: true)

                Button(NSLocalizedString("Close", comment: "Go to Line close button")) {
                    onClose()
                    dismiss()
                }
                .buttonStyle(.plain)
                .searchPanelActionButton()
            }
        }
        .padding(18)
        .frame(minWidth: 320)
        .onAppear {
            lineFieldFocused = true
            validationMessage = ""
        }
    }
}

struct GoToSymbolPanel: View {
    @Binding var query: String
    let items: [DocumentSymbolItem]
    let onSelect: (DocumentSymbolItem) -> Void
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var queryFieldFocused: Bool
    @State private var selectedItemID: DocumentSymbolItem.ID?

    private var selectedItem: DocumentSymbolItem? {
        guard let selectedItemID else { return items.first }
        return items.first(where: { $0.id == selectedItemID }) ?? items.first
    }

    private func syncSelectionToVisibleItems() {
        guard let selectedItemID, items.contains(where: { $0.id == selectedItemID }) else {
            self.selectedItemID = items.first?.id
            return
        }
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        syncSelectionToVisibleItems()
        let currentIndex = items.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        selectedItemID = items[nextIndex].id
    }

    private func submitPrimarySelection() {
        guard let item = selectedItem, item.line != nil else { return }
        onSelect(item)
        dismiss()
    }

    @ViewBuilder
    private func applyMoveCommand<Content: View>(to content: Content) -> some View {
#if os(macOS)
        content.onMoveCommand { direction in
            switch direction {
            case .down:
                moveSelection(by: 1)
            case .up:
                moveSelection(by: -1)
            default:
                break
            }
        }
#else
        content
#endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            applyMoveCommand(to:
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("Go to Symbol", comment: "Go to Symbol panel title"))
                        .font(.headline)

                    TextField(NSLocalizedString("Search current document symbols", comment: "Go to Symbol search placeholder"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($queryFieldFocused)
                        .onSubmit { submitPrimarySelection() }
                        .accessibilityLabel(NSLocalizedString("Go to Symbol Search", comment: "Go to Symbol accessibility label"))
                        .accessibilityHint(NSLocalizedString("Type to filter symbols in the current document. Use Up and Down Arrow to move through results.", comment: "Go to Symbol accessibility hint"))

                    List(items) { item in
                        Button {
                            selectedItemID = item.id
                            guard item.line != nil else { return }
                            onSelect(item)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .lineLimit(1)
                                Text(item.line.map { "Line \($0)" } ?? NSLocalizedString("Unavailable", comment: "Unavailable symbol line"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .id(item.id)
                        .buttonStyle(.plain)
                        .disabled(item.line == nil)
                        .listRowBackground(
                            selectedItemID == item.id
                            ? NeonUIStyle.selectedRowFill(for: colorScheme)
                            : Color.clear
                        )
                        .onTapGesture {
                            selectedItemID = item.id
                        }
                        .accessibilityLabel(item.title)
                        .accessibilityValue(item.line.map { "Line \($0)" } ?? NSLocalizedString("No line", comment: "No line accessibility value"))
                        .accessibilityHint(NSLocalizedString("Jump to this symbol in the current document.", comment: "Go to Symbol row accessibility hint"))
                    }
                    .listStyle(.plain)

                    HStack {
                        Text(String.localizedStringWithFormat(NSLocalizedString("%lld symbols", comment: "Go to Symbol count"), Int64(items.filter { $0.line != nil }.count)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(NSLocalizedString("Close", comment: "Go to Symbol close button")) {
                            onClose()
                            dismiss()
                        }
                    }
                }
#if os(iOS)
                .background(
                    DirectionalKeyCommandBridge(
                        onMoveUp: { moveSelection(by: -1) },
                        onMoveDown: { moveSelection(by: 1) }
                    )
                    .frame(width: 0, height: 0)
                )
#endif
                .padding(16)
                .frame(minWidth: 520, minHeight: 380)
                .onAppear {
                    queryFieldFocused = true
                    syncSelectionToVisibleItems()
                }
                .onChange(of: items.map(\.id)) { _, _ in
                    syncSelectionToVisibleItems()
                }
                .onChange(of: selectedItemID) { _, newValue in
                    guard let newValue else { return }
                    proxy.scrollTo(newValue, anchor: .center)
                }
            )
        }
    }
}

struct FindInFilesMatch: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let line: Int
    let column: Int
    let snippet: String
    let rangeLocation: Int
    let rangeLength: Int
}

struct FindInFilesPanel: View {
    @Binding var query: String
    @Binding var caseSensitive: Bool
    @Binding var replaceQuery: String
    @Binding var selectedMatchIDs: Set<String>
    let results: [FindInFilesMatch]
    let statusMessage: String
    let sourceMessage: String
    let isApplyingReplace: Bool
    let onSearch: () -> Void
    let onClear: () -> Void
    let onToggleSelection: (String) -> Void
    let onSelectAll: () -> Void
    let onSelectNone: () -> Void
    let onApplyReplace: () -> Void
    let onCancelReplace: () -> Void
    let onSelect: (FindInFilesMatch) -> Void
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var queryFieldFocused: Bool
    @State private var selectedMatchID: FindInFilesMatch.ID?

    private var usesCompactPhoneLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
#else
        false
#endif
    }

    private var hasSearched: Bool {
        !normalizedQuery.isEmpty
    }

    private struct MatchGroup: Identifiable {
        let fileURL: URL
        let matches: [FindInFilesMatch]

        var id: String { fileURL.standardizedFileURL.path }
        var matchCountText: String { matches.count == 1 ? "1 hit" : "\(matches.count) hits" }
    }

    private func submitPrimaryAction() {
        guard let match = selectedMatch else {
            onSearch()
            return
        }
        onSelect(match)
        onClose()
    }

    private var selectedMatch: FindInFilesMatch? {
        guard let selectedMatchID else { return results.first }
        return results.first(where: { $0.id == selectedMatchID }) ?? results.first
    }

    private func syncSelectionToVisibleResults() {
        guard let selectedMatchID,
              results.contains(where: { $0.id == selectedMatchID }) else {
            self.selectedMatchID = results.first?.id
            return
        }
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        syncSelectionToVisibleResults()
        let currentIndex = results.firstIndex(where: { $0.id == selectedMatchID }) ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), results.count - 1)
        selectedMatchID = results[nextIndex].id
    }

    private var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedCount: Int {
        results.reduce(into: 0) { partialResult, match in
            if selectedMatchIDs.contains(match.id) {
                partialResult += 1
            }
        }
    }

    private var usesPadLayout: Bool {
#if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
#else
        false
#endif
    }

    private var groupedResults: [MatchGroup] {
        var groups: [MatchGroup] = []
        var groupedMatches: [String: [FindInFilesMatch]] = [:]

        for match in results {
            let key = match.fileURL.standardizedFileURL.path
            groupedMatches[key, default: []].append(match)
        }

        var seen: Set<String> = []
        for match in results {
            let key = match.fileURL.standardizedFileURL.path
            guard !seen.contains(key), let matches = groupedMatches[key] else { continue }
            groups.append(MatchGroup(fileURL: match.fileURL, matches: matches))
            seen.insert(key)
        }

        return groups
    }

    @ViewBuilder
    private var centeredTitleHeader: some View {
        Text(NSLocalizedString("Find in Files", comment: ""))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func highlightedText(_ text: String) -> Text {
        let searchTerm = normalizedQuery
        let baseColor = Color.primary.opacity(colorScheme == .dark ? 0.88 : 0.78)
        guard !searchTerm.isEmpty else { return Text(text).foregroundColor(baseColor) }

        let compareOptions: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var rendered = Text("")
        var remaining = text[...]

        while let range = remaining.range(of: searchTerm, options: compareOptions) {
            let prefix = String(remaining[..<range.lowerBound])
            let match = String(remaining[range])
            if !prefix.isEmpty {
                rendered = rendered + Text(prefix).foregroundColor(baseColor)
            }
            rendered = rendered + Text(match)
                .foregroundColor(NeonUIStyle.accentBlueStrong)
                .fontWeight(.semibold)
                .underline()
            remaining = remaining[range.upperBound...]
        }

        if !remaining.isEmpty {
            rendered = rendered + Text(String(remaining)).foregroundColor(baseColor)
        }
        return rendered
    }

    private func abbreviatedPath(for fileURL: URL) -> String {
        let components = fileURL.standardizedFileURL.pathComponents
        guard components.count > 4 else { return fileURL.deletingLastPathComponent().path }
        let suffix = components.dropLast().suffix(4).joined(separator: "/")
        return "…/\(suffix)"
    }

    private func groupHeaderSubtitle(for fileURL: URL) -> String {
        let directoryPath = fileURL.deletingLastPathComponent()
        let components = directoryPath.standardizedFileURL.pathComponents
        guard components.count > 4 else { return directoryPath.path }
        let suffix = components.suffix(4).joined(separator: "/")
        return "…/\(suffix)"
    }

    @ViewBuilder
    private var phoneSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField(NSLocalizedString("Search project files", comment: ""), text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitPrimaryAction() }
                .accessibilityLabel(NSLocalizedString("Find in Files Search", comment: ""))
                .accessibilityHint(NSLocalizedString("Enter text to search across project files. Use Up and Down Arrow to move through results. Press Return to open the selected result.", comment: ""))
                .focused($queryFieldFocused)

            TextField(NSLocalizedString("Replace with", comment: ""), text: $replaceQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(NSLocalizedString("Find in Files Replacement", comment: ""))
                .accessibilityHint(NSLocalizedString("Enter replacement text to apply to selected project matches.", comment: ""))

            Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)
                .accessibilityLabel(NSLocalizedString("Case Sensitive Search", comment: ""))
        }
        .padding(14)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var phoneStatusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusMessage)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            if !sourceMessage.isEmpty {
                Text(sourceMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var phoneActionSection: some View {
        HStack(spacing: 10) {
            Button(NSLocalizedString("Search", comment: "")) { onSearch() }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(maxWidth: .infinity)
                .searchPanelActionButton(prominent: true)

            Button(NSLocalizedString("Clear", comment: "")) { onClear() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton()

            Button(NSLocalizedString("Close", comment: "")) { onClose() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .frame(maxWidth: .infinity)
                .searchPanelActionButton()
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var padSearchSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                TextField(NSLocalizedString("Search project files", comment: ""), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitPrimaryAction() }
                    .accessibilityLabel(NSLocalizedString("Find in Files Search", comment: ""))
                    .accessibilityHint(NSLocalizedString("Enter text to search across project files. Use Up and Down Arrow to move through results. Press Return to open the selected result.", comment: ""))
                    .focused($queryFieldFocused)

                Button(NSLocalizedString("Search", comment: "")) { onSearch() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .searchPanelActionButton(prominent: true)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(NSLocalizedString("Clear", comment: "")) { onClear() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .searchPanelActionButton()
                    .accessibilityLabel(NSLocalizedString("Clear Search", comment: ""))
            }

            TextField(NSLocalizedString("Replace with", comment: ""), text: $replaceQuery)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(NSLocalizedString("Find in Files Replacement", comment: ""))
                .accessibilityHint(NSLocalizedString("Enter replacement text to apply to selected project matches.", comment: ""))

            Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)
                .accessibilityLabel(NSLocalizedString("Case Sensitive Search", comment: ""))
        }
        .padding(18)
        .subtleSearchSectionCard()
    }

    @ViewBuilder
    private var padFooterSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusMessage)
                if !sourceMessage.isEmpty {
                    Text(sourceMessage)
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            Button(NSLocalizedString("Clear", comment: "")) { onClear() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .searchPanelActionButton()

            Button(NSLocalizedString("Close", comment: "")) { onClose() }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .searchPanelActionButton()
        }
    }

    @ViewBuilder
    private func applyMoveCommand<Content: View>(to content: Content) -> some View {
#if os(macOS)
        content.onMoveCommand { direction in
            switch direction {
            case .down:
                moveSelection(by: 1)
            case .up:
                moveSelection(by: -1)
            default:
                break
            }
        }
#else
        content
#endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            applyMoveCommand(to:
                VStack(alignment: .leading, spacing: 12) {
                centeredTitleHeader

                if usesCompactPhoneLayout {
                    phoneSearchSection
                    phoneStatusSection
                } else if usesPadLayout {
                    padSearchSection
                } else {
                    HStack(spacing: 8) {
                        TextField(NSLocalizedString("Search project files", comment: ""), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { submitPrimaryAction() }
                            .accessibilityLabel(NSLocalizedString("Find in Files Search", comment: ""))
                            .accessibilityHint(NSLocalizedString("Enter text to search across project files. Use Up and Down Arrow to move through results. Press Return to open the selected result.", comment: ""))
                            .focused($queryFieldFocused)

                        Button(NSLocalizedString("Search", comment: "")) { onSearch() }
                            .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel(NSLocalizedString("Search Files", comment: ""))
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .searchPanelActionButton(prominent: true)

                        Button(NSLocalizedString("Clear", comment: "")) { onClear() }
                            .accessibilityLabel(NSLocalizedString("Clear Search", comment: ""))
                            .buttonStyle(.plain)
                            .font(.caption.weight(.medium))
                            .searchPanelActionButton()
                    }

                    Toggle(NSLocalizedString("Case Sensitive", comment: ""), isOn: $caseSensitive)
                        .accessibilityLabel(NSLocalizedString("Case Sensitive Search", comment: ""))
                }

                List {
                    if groupedResults.isEmpty, hasSearched {
                        ContentUnavailableView(
                            NSLocalizedString("No Matches Found", comment: ""),
                            systemImage: "text.magnifyingglass",
                            description: Text(statusMessage)
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(groupedResults) { group in
                            Section {
                                ForEach(group.matches) { match in
                                    HStack(alignment: .top, spacing: 8) {
                                        Button {
                                            onToggleSelection(match.id)
                                        } label: {
                                            Image(systemName: selectedMatchIDs.contains(match.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedMatchIDs.contains(match.id) ? NeonUIStyle.accentBlueStrong : .secondary)
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(selectedMatchIDs.contains(match.id) ? NSLocalizedString("Deselect Match", comment: "") : NSLocalizedString("Select Match", comment: ""))
                                        .accessibilityHint(NSLocalizedString("Toggle this result for project-wide replace.", comment: ""))

                                        Button {
                                            selectedMatchID = match.id
                                            onSelect(match)
                                            onClose()
                                        } label: {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text("Line \(match.line), Column \(match.column)")
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                highlightedText(match.snippet)
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .lineLimit(2)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .id(match.id)
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(group.fileURL.lastPathComponent) line \(match.line) column \(match.column)")
                                        .accessibilityValue(match.snippet)
                                        .accessibilityHint(NSLocalizedString("Open match in editor", comment: ""))
                                    }
                                    .listRowBackground(
                                        selectedMatchID == match.id
                                        ? NeonUIStyle.selectedRowFill(for: colorScheme)
                                        : Color.clear
                                    )
                                    .onTapGesture {
                                        selectedMatchID = match.id
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(group.fileURL.lastPathComponent)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(group.matchCountText)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(NeonUIStyle.accentBlueStrong)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule()
                                                    .fill(NeonUIStyle.searchMatchFill(for: colorScheme))
                                            )
                                    }
                                    Text(groupHeaderSubtitle(for: group.fileURL))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.top, 4)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(group.fileURL.lastPathComponent)
                                .accessibilityValue(groupHeaderSubtitle(for: group.fileURL))
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .accessibilityLabel(NSLocalizedString("Find in Files Results", comment: ""))
                .subtleSearchSectionCard()

                if usesCompactPhoneLayout {
                    phoneActionSection
                } else if usesPadLayout {
                    padFooterSection
                } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusMessage)
                        if !sourceMessage.isEmpty {
                                Text(sourceMessage)
                                    .font(.caption2)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Clear", comment: "")) { onClear() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                    Button(NSLocalizedString("Close", comment: "")) { onClose() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                }
                }

                HStack(spacing: 8) {
                    Text(String.localizedStringWithFormat(NSLocalizedString("%lld selected", comment: ""), Int64(selectedCount)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Select All", comment: "")) { onSelectAll() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                        .disabled(results.isEmpty || isApplyingReplace)
                    Button(NSLocalizedString("Select None", comment: "")) { onSelectNone() }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .searchPanelActionButton()
                        .disabled(selectedCount == 0 || isApplyingReplace)
                    if isApplyingReplace {
                        Button(NSLocalizedString("Cancel", comment: "")) { onCancelReplace() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .searchPanelActionButton()
                    } else {
                        Button(NSLocalizedString("Apply Selected", comment: "")) { onApplyReplace() }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .searchPanelActionButton(prominent: true)
                            .disabled(selectedCount == 0 || normalizedQuery.isEmpty)
                            .accessibilityLabel(NSLocalizedString("Apply Selected Replacements", comment: ""))
                            .accessibilityHint(NSLocalizedString("Replace text for selected project matches only.", comment: ""))
                    }
                }
            }
#if os(iOS)
            .background(
                DirectionalKeyCommandBridge(
                    onMoveUp: { moveSelection(by: -1) },
                    onMoveDown: { moveSelection(by: 1) }
                )
                .frame(width: 0, height: 0)
            )
#endif
            .padding(16)
#if os(macOS)
            .frame(minWidth: 620, minHeight: 560)
#else
            .frame(maxWidth: .infinity, minHeight: usesCompactPhoneLayout ? 460 : (usesPadLayout ? 620 : 420))
#endif
            .subtleSearchPanelSurface()
            .onAppear {
                queryFieldFocused = true
                syncSelectionToVisibleResults()
            }
            .onChange(of: results.map(\.id)) { _, _ in
                syncSelectionToVisibleResults()
                selectedMatchIDs = selectedMatchIDs.intersection(Set(results.map(\.id)))
            }
            .onChange(of: selectedMatchID) { _, newValue in
                guard let newValue else { return }
                proxy.scrollTo(newValue, anchor: .center)
            }
            )
        }
    }
}

#if canImport(UIKit)
private struct DirectionalKeyCommandBridge: UIViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    func makeUIView(context: Context) -> DirectionalKeyCommandView {
        let view = DirectionalKeyCommandView()
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        return view
    }

    func updateUIView(_ uiView: DirectionalKeyCommandView, context: Context) {
        uiView.onMoveUp = onMoveUp
        uiView.onMoveDown = onMoveDown
        uiView.refreshFirstResponderStatus()
    }
}

private final class DirectionalKeyCommandView: UIView {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override var keyCommands: [UIKeyCommand]? {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return [] }
        let upCommand = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleMoveUp))
        upCommand.discoverabilityTitle = "Move Up"
        let downCommand = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleMoveDown))
        downCommand.discoverabilityTitle = "Move Down"
        return [upCommand, downCommand]
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshFirstResponderStatus()
    }

    func refreshFirstResponderStatus() {
        guard window != nil, UIDevice.current.userInterfaceIdiom == .pad else { return }
        DispatchQueue.main.async { [weak self] in
            _ = self?.becomeFirstResponder()
        }
    }

    @objc private func handleMoveUp() {
        onMoveUp?()
    }

    @objc private func handleMoveDown() {
        onMoveDown?()
    }
}
#endif

struct WelcomeTourView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager

    static var releaseID: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    struct ToolbarItemInfo: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let shortcutMac: String
        let shortcutPad: String
        let iconName: String
    }

    struct TourPage: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let bullets: [String]
        let iconName: String
        let colors: [Color]
        let toolbarItems: [ToolbarItemInfo]
    }

    let onFinish: () -> Void
    @State private var selectedIndex: Int = 0

    private let pages: [TourPage] = [
        TourPage(
            title: "What’s New in This Release",
            subtitle: "Major changes since v0.6.1:",
            bullets: [
                "Find-in-files now supports selective project-wide replace with explicit preview and cancellation controls.",
                "Navigation and edit workflows are faster with direct `Go to Line` and `Go to Symbol` commands.",
                "macOS sidebar and tour overlays are more comfortable and consistent for daily keyboard/mouse use.",
                "Project sidebar disclosure controls now align better with file rows and are easier to recognize."
            ],
            iconName: "sparkles.rectangle.stack",
            colors: [Color(red: 0.40, green: 0.28, blue: 0.90), Color(red: 0.96, green: 0.46, blue: 0.55)],
            toolbarItems: []
        ),
        TourPage(
            title: "Support Neo Vision Editor",
            subtitle: "Keep it free, sustainable, and improving.",
            bullets: [
                "Neo Vision Editor will always stay free to use.",
                "No subscriptions and no paywalls.",
                "Keeping the app alive still has real costs: Apple Developer Program fee, maintenance, updates, and long-term support.",
                "⭐ Optional Support Tip (Consumable) — $4.99",
                "Tip can be purchased multiple times.",
                "Your support helps cover: Apple developer fees, bug fixes and updates, future improvements and features, and long-term support.",
                "Thank you for helping keep Neo Vision Editor free for everyone."
            ],
            iconName: "heart.circle.fill",
            colors: [Color(red: 0.98, green: 0.33, blue: 0.49), Color(red: 1.00, green: 0.64, blue: 0.30)],
            toolbarItems: []
        ),
        TourPage(
            title: "A Fast, Focused Editor",
            subtitle: "Built for quick edits and flow.",
            bullets: [
                "Tabbed editing with per-file language support",
                "Automatic syntax highlighting for many formats",
                "Word count, caret status, and complete toolbar options",
                "Large-file scrolling and highlighting tuned with shared regex caching and incremental refresh paths",
                "Line-number gutter performance improved on macOS and iOS for long documents"
            ],
            iconName: "doc.text.magnifyingglass",
            colors: [Color(red: 0.96, green: 0.48, blue: 0.28), Color(red: 0.99, green: 0.78, blue: 0.35)],
            toolbarItems: []
        ),
        TourPage(
            title: "Smart Assistance",
            subtitle: "Use local or cloud AI models when you want.",
            bullets: [
                "Apple Intelligence integration (when available)",
                "Optional Grok, OpenAI, Gemini, and Anthropic providers",
                "AI providers are used for simple code completion and suggestions",
                "API keys stored securely in Keychain",
                "Curated popular built-in themes: Dracula, One Dark Pro, Nord, Tokyo Night, and Gruvbox",
                "Neon Glow readability and token colors tuned for both Light and Dark appearance"
            ],
            iconName: "sparkles",
            colors: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.21, green: 0.86, blue: 0.78)],
            toolbarItems: []
        ),
        TourPage(
            title: "Power User Features",
            subtitle: "Navigate large projects quickly.",
            bullets: [
                "Quick Open with Cmd+P",
                "All sidebars: document outline and project structure",
                "Find & Replace and full editor/view toolbar actions",
                "Lightweight Vim-style workflow support on macOS"
            ],
            iconName: "bolt.circle",
            colors: [Color(red: 0.22, green: 0.72, blue: 0.43), Color(red: 0.08, green: 0.42, blue: 0.73)],
            toolbarItems: []
        ),
        TourPage(
            title: "Toolbar Map",
            subtitle: "Every button, plus the quickest way to reach it.",
            bullets: [
                "Shortcuts are shown where available",
                "iPad hardware-keyboard shortcuts are shown where supported; no shortcut? the toolbar is the fastest path"
            ],
            iconName: "slider.horizontal.3",
            colors: [Color(red: 0.36, green: 0.32, blue: 0.92), Color(red: 0.92, green: 0.49, blue: 0.64)],
            toolbarItems: [
                ToolbarItemInfo(title: "New Window", description: "New Window", shortcutMac: "Cmd+N", shortcutPad: "None", iconName: "macwindow.badge.plus"),
                ToolbarItemInfo(title: "New Tab", description: "New Tab", shortcutMac: "Cmd+T", shortcutPad: "Cmd+T", iconName: "plus.square.on.square"),
                ToolbarItemInfo(title: "Open File…", description: "Open File…", shortcutMac: "Cmd+O", shortcutPad: "Cmd+O", iconName: "folder"),
                ToolbarItemInfo(title: "Save File", description: "Save File", shortcutMac: "Cmd+S", shortcutPad: "Cmd+S", iconName: "square.and.arrow.down"),
                ToolbarItemInfo(title: "Settings", description: "Settings", shortcutMac: "Cmd+,", shortcutPad: "None", iconName: "gearshape"),
                ToolbarItemInfo(title: "Insert Template", description: "Insert Template for Current Language", shortcutMac: "None", shortcutPad: "None", iconName: "doc.badge.plus"),
                ToolbarItemInfo(title: "Language", description: "Language", shortcutMac: "None", shortcutPad: "None", iconName: "textformat"),
                ToolbarItemInfo(title: "AI Model & Settings", description: "AI Model & Settings", shortcutMac: "None", shortcutPad: "None", iconName: "brain.head.profile"),
                ToolbarItemInfo(title: "Code Completion", description: "Enable Code Completion / Disable Code Completion", shortcutMac: "None", shortcutPad: "None", iconName: "bolt.horizontal.circle"),
                ToolbarItemInfo(title: "Find & Replace", description: "Find & Replace", shortcutMac: "Cmd+F", shortcutPad: "Cmd+F", iconName: "magnifyingglass"),
                ToolbarItemInfo(title: "Toggle Sidebar", description: "Toggle Sidebar", shortcutMac: "Cmd+Opt+S", shortcutPad: "Cmd+Opt+S", iconName: "sidebar.left"),
                ToolbarItemInfo(title: "Project Sidebar", description: "Toggle Project Structure Sidebar", shortcutMac: "None", shortcutPad: "None", iconName: "sidebar.right"),
                ToolbarItemInfo(title: "Line Wrap", description: "Enable Wrap / Disable Wrap", shortcutMac: "Cmd+Opt+L", shortcutPad: "Cmd+Opt+L", iconName: "text.justify"),
                ToolbarItemInfo(title: "Clear Editor", description: "Clear Editor", shortcutMac: "None", shortcutPad: "None", iconName: "eraser")
            ]
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(pages.enumerated()), id: \.offset) { idx, page in
                    tourCard(for: page)
                        .tag(idx)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                }
            }
#if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .never))
#else
            .tabViewStyle(.automatic)
#endif

            HStack(spacing: 8) {
                ForEach(0..<pages.count, id: \.self) { idx in
                    Capsule()
                        .fill(idx == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: idx == selectedIndex ? 14 : 6, height: 5)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 10)

            HStack {
                Button("Skip") { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                if selectedIndex < pages.count - 1 {
                    Button("Next") {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedIndex += 1
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { onFinish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 0.09, green: 0.10, blue: 0.14), Color(red: 0.13, green: 0.16, blue: 0.22)]
                    : [Color(red: 0.98, green: 0.99, blue: 1.00), Color(red: 0.93, green: 0.96, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
#if os(macOS)
        .frame(minWidth: 920, minHeight: 680)
#else
        .presentationDetents([.large])
#endif
    }

    @ViewBuilder
    private func tourCard(for page: TourPage) -> some View {
        let displayBullets = page.bullets.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("![") }
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 56, height: 56)
                        Image(systemName: page.iconName)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(page.title)
                            .font(.system(size: 28, weight: .bold))
                        Text(page.subtitle)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 10)

                if page.title == "Toolbar Map" && displayBullets.count >= 2 {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            bulletRow(displayBullets[0])
                            Text("scroll for viewing all toolbar options.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        bulletRow(displayBullets[1])
                    }
                    .padding(.bottom, 0)
                } else {
                    ForEach(displayBullets, id: \.self) { bullet in
                        bulletRow(bullet)
                    }
                }

                if page.title == "Support Neo Vision Editor" {
                    supportPurchaseCard
                        .padding(.top, 6)
                }

                if !page.toolbarItems.isEmpty {
                    toolbarGrid(items: page.toolbarItems)
                        .padding(.top, page.title == "Toolbar Map" ? -8 : 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(colorScheme == .dark ? .regularMaterial : .ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.55),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                    radius: 18,
                    x: 0,
                    y: 8
                )
        )
    }

    @ViewBuilder
    private var supportPurchaseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Task { await supportPurchaseManager.purchaseSupport() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Send Support Tip — \(supportPurchaseManager.supportPriceLabel)")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                shouldDisableSupportPurchaseButton
            )

            if let status = supportPurchaseManager.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !supportPurchaseManager.canUseInAppPurchases {
                Text(NSLocalizedString("In-App Purchases are currently unavailable on this device. Check App Store login and Screen Time restrictions.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let externalURL = SupportPurchaseManager.externalSupportURL {
                Button {
                    openURL(externalURL)
                } label: {
                    Label(NSLocalizedString("Support via Patreon", comment: ""), systemImage: "safari")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
    }

    private var shouldDisableSupportPurchaseButton: Bool {
#if os(iOS)
        supportPurchaseManager.isPurchasing
#else
        supportPurchaseManager.isPurchasing
        || supportPurchaseManager.isLoadingProducts
        || !supportPurchaseManager.canUseInAppPurchases
#endif
    }

    private func toolbarGrid(items: [ToolbarItemInfo]) -> some View {
        return GeometryReader { proxy in
            let isCompact = proxy.size.width < 640
            let columns = isCompact
                ? [GridItem(.flexible(), spacing: 12)]
                : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            let dynamicMax = max(240, min(520, proxy.size.height * 0.6))
            let maxGridHeight: CGFloat = isCompact ? min(dynamicMax, 360) : dynamicMax
            let innerHeight = maxGridHeight + 180
            let innerFill = Color.white.opacity(colorScheme == .dark ? 0.02 : 0.25)
            let innerStroke = Color.white.opacity(colorScheme == .dark ? 0.12 : 0.15)

            VStack(alignment: .leading, spacing: 12) {
                Text("Toolbar buttons")
                    .font(.system(size: 16, weight: .semibold))

                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            toolbarItemRow(item)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: maxGridHeight)
                .clipped()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(innerFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(innerStroke, lineWidth: 1)
                    )
            )
            .frame(height: innerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 7, height: 7)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 15))
        }
    }

    private func toolbarItemRow(_ item: ToolbarItemInfo) -> some View {
        let cardFill = colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.8)
        let cardStroke = colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        let shortcut = isPadShortcut ? item.shortcutPad : item.shortcutMac

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                    shortcutCapsule(shortcut)
                }
                Text(item.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )
        )
    }

    private var isPadShortcut: Bool {
#if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
#else
        return false
#endif
    }

    private func shortcutCapsule(_ shortcut: String) -> some View {
        let trimmed = shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNone = trimmed.isEmpty || trimmed.caseInsensitiveCompare("none") == .orderedSame
        let parts = trimmed.split(separator: "+").map { String($0) }

        return Group {
            if !isNone {
                HStack(spacing: 4) {
                    ForEach(parts, id: \.self) { part in
                        Text(part)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
                            )
                    }
                }
            }
        }
    }
}

struct SupportPromptSheetView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var supportPurchaseManager: SupportPurchaseManager
    let onDismiss: () -> Void

    private let bullets: [String] = [
        "Neo Vision Editor will always stay free to use.",
        "No subscriptions and no paywalls.",
        "Keeping the app alive still has real costs: Apple Developer Program fee, maintenance, updates, and long-term support.",
        "Your support helps cover: Apple developer fees, bug fixes and updates, future improvements and features, and long-term support."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Support Neo Vision Editor")
                        .font(.title2.weight(.bold))
                    Text("Keep it free, sustainable, and improving.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.9))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(bullet)
                        .font(.body)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await supportPurchaseManager.purchaseSupport() }
                } label: {
                    Label("Send Support Tip — \(supportPurchaseManager.supportPriceLabel)", systemImage: "heart.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(supportPurchaseManager.isPurchasing || supportPurchaseManager.isLoadingProducts)

                if let externalURL = SupportPurchaseManager.externalSupportURL {
                    Button {
                        openURL(externalURL)
                    } label: {
                        Label("Support via Patreon", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                if let status = supportPurchaseManager.statusMessage, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
            )

            HStack {
                Spacer()
                Button("Not Now") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .onAppear {
            Task { await supportPurchaseManager.refreshPrice() }
        }
#if os(macOS)
        .frame(minWidth: 560, minHeight: 420)
#else
        .presentationDetents([.medium, .large])
#endif
    }
}

struct EditorHelpView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let toolbarItems: [WelcomeTourView.ToolbarItemInfo] = [
        .init(title: "New Window", description: "Open a new editor window.", shortcutMac: "Cmd+N", shortcutPad: "None", iconName: "macwindow.badge.plus"),
        .init(title: "New Tab", description: "Create a new tab in the current window.", shortcutMac: "Cmd+T", shortcutPad: "Cmd+T", iconName: "plus.square.on.square"),
        .init(title: "Open File…", description: "Open a single file.", shortcutMac: "Cmd+O", shortcutPad: "Cmd+O", iconName: "folder"),
        .init(title: "Save File", description: "Save current file.", shortcutMac: "Cmd+S", shortcutPad: "Cmd+S", iconName: "square.and.arrow.down"),
        .init(title: "Settings", description: "Open app settings.", shortcutMac: "Cmd+,", shortcutPad: "None", iconName: "gearshape"),
        .init(title: "Insert Template", description: "Insert template for current language.", shortcutMac: "None", shortcutPad: "None", iconName: "doc.badge.plus"),
        .init(title: "Language", description: "Change syntax language mode.", shortcutMac: "None", shortcutPad: "None", iconName: "textformat"),
        .init(title: "AI Model & Settings", description: "Select AI model and provider setup.", shortcutMac: "None", shortcutPad: "None", iconName: "brain.head.profile"),
        .init(title: "Code Completion", description: "Enable or disable AI-assisted completion.", shortcutMac: "None", shortcutPad: "None", iconName: "bolt.horizontal.circle"),
        .init(title: "Find & Replace", description: "Search and replace within the current file.", shortcutMac: "Cmd+F", shortcutPad: "Cmd+F", iconName: "magnifyingglass"),
        .init(title: "Quick Open", description: "Open file quickly by name.", shortcutMac: "Cmd+P", shortcutPad: "Cmd+P", iconName: "magnifyingglass.circle"),
        .init(title: "Go to Line", description: "Jump directly to a line in the current file.", shortcutMac: "Cmd+L", shortcutPad: "Cmd+L", iconName: "text.line.first.and.arrowtriangle.forward"),
        .init(title: "Go to Symbol", description: "Jump to a symbol in the current document.", shortcutMac: "Cmd+Shift+J", shortcutPad: "Cmd+Shift+J", iconName: "list.bullet.indent"),
        .init(title: "Toggle Sidebar", description: "Show or hide file sidebar.", shortcutMac: "Cmd+Opt+S", shortcutPad: "Cmd+Opt+S", iconName: "sidebar.left"),
        .init(title: "Project Sidebar", description: "Toggle project structure sidebar.", shortcutMac: "None", shortcutPad: "None", iconName: "sidebar.right"),
        .init(title: "Line Wrap", description: "Enable or disable line wrapping.", shortcutMac: "Cmd+Opt+L", shortcutPad: "Cmd+Opt+L", iconName: "text.justify"),
        .init(title: "Clear Editor", description: "Clear current editor content.", shortcutMac: "None", shortcutPad: "None", iconName: "eraser")
    ]

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Editor Help")
                            .font(.largeTitle.weight(.bold))
                        Text("All core editor actions and keyboard shortcuts in one place.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(toolbarItems) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    shortcutCapsule("macOS: \(item.shortcutMac)")
                                    shortcutCapsule("iPad: \(item.shortcutPad)")
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03))
                        )
                    }
                }
                .padding(20)
            }
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .automatic) {
                    Button("Done") { onDismiss() }
                }
                #else
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
                }
                #endif
            }
        }
#if os(macOS)
        .frame(minWidth: 760, minHeight: 620)
#else
        .presentationDetents([.large])
#endif
    }

    private func shortcutCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
            )
    }
}

extension Notification.Name {
    static let moveCursorToLine = Notification.Name("moveCursorToLine")
    static let caretPositionDidChange = Notification.Name("caretPositionDidChange")
    static let pastedText = Notification.Name("pastedText")
    static let toggleTranslucencyRequested = Notification.Name("toggleTranslucencyRequested")
    static let clearEditorRequested = Notification.Name("clearEditorRequested")
    static let showFindReplaceRequested = Notification.Name("showFindReplaceRequested")
    static let findNextRequested = Notification.Name("findNextRequested")
    static let toggleProjectStructureSidebarRequested = Notification.Name("toggleProjectStructureSidebarRequested")
    static let openProjectFolderRequested = Notification.Name("openProjectFolderRequested")
    static let showAPISettingsRequested = Notification.Name("showAPISettingsRequested")
    static let selectAIModelRequested = Notification.Name("selectAIModelRequested")
    static let showQuickSwitcherRequested = Notification.Name("showQuickSwitcherRequested")
    static let showFindInFilesRequested = Notification.Name("showFindInFilesRequested")
    static let showGoToLineRequested = Notification.Name("showGoToLineRequested")
    static let showGoToSymbolRequested = Notification.Name("showGoToSymbolRequested")
    static let showWelcomeTourRequested = Notification.Name("showWelcomeTourRequested")
    static let showEditorHelpRequested = Notification.Name("showEditorHelpRequested")
    static let showSupportPromptRequested = Notification.Name("showSupportPromptRequested")
    static let moveCursorToRange = Notification.Name("moveCursorToRange")
    static let toggleVimModeRequested = Notification.Name("toggleVimModeRequested")
    static let vimModeStateDidChange = Notification.Name("vimModeStateDidChange")
    static let droppedFileURL = Notification.Name("droppedFileURL")
    static let droppedFileLoadStarted = Notification.Name("droppedFileLoadStarted")
    static let droppedFileLoadProgress = Notification.Name("droppedFileLoadProgress")
    static let droppedFileLoadFinished = Notification.Name("droppedFileLoadFinished")
    static let toggleSidebarRequested = Notification.Name("toggleSidebarRequested")
    static let toggleBrainDumpModeRequested = Notification.Name("toggleBrainDumpModeRequested")
    static let zoomEditorFontRequested = Notification.Name("zoomEditorFontRequested")
    static let inspectWhitespaceScalarsRequested = Notification.Name("inspectWhitespaceScalarsRequested")
    static let addNextMatchRequested = Notification.Name("addNextMatchRequested")
    static let whitespaceScalarInspectionResult = Notification.Name("whitespaceScalarInspectionResult")
    static let insertBracketHelperTokenRequested = Notification.Name("insertBracketHelperTokenRequested")
    static let keyboardAccessoryBarVisibilityChanged = Notification.Name("keyboardAccessoryBarVisibilityChanged")
    static let showUpdaterRequested = Notification.Name("showUpdaterRequested")
    static let showSettingsRequested = Notification.Name("showSettingsRequested")
    static let closeSelectedTabRequested = Notification.Name("closeSelectedTabRequested")
    static let openRecentFileRequested = Notification.Name("openRecentFileRequested")
    static let recentFilesDidChange = Notification.Name("recentFilesDidChange")
}

extension NSRange {
    func toOptional() -> NSRange? { self.location == NSNotFound ? nil : self }
}

enum EditorCommandUserInfo {
    static let windowNumber = "targetWindowNumber"
    static let inspectionMessage = "inspectionMessage"
    static let rangeLocation = "rangeLocation"
    static let rangeLength = "rangeLength"
    static let focusEditor = "focusEditor"
    static let bracketToken = "bracketToken"
    static let updaterCheckNow = "updaterCheckNow"
}

#if os(macOS)
private final class WeakEditorViewModelRef {
    weak var value: EditorViewModel?
    init(_ value: EditorViewModel) { self.value = value }
}

@MainActor
final class WindowViewModelRegistry {
    static let shared = WindowViewModelRegistry()
    private var storage: [Int: WeakEditorViewModelRef] = [:]

    private init() {}

    func register(_ viewModel: EditorViewModel, for windowNumber: Int) {
        storage[windowNumber] = WeakEditorViewModelRef(viewModel)
    }

    func unregister(windowNumber: Int) {
        storage.removeValue(forKey: windowNumber)
    }

    func viewModel(for windowNumber: Int?) -> EditorViewModel? {
        guard let windowNumber else { return nil }
        if let vm = storage[windowNumber]?.value {
            return vm
        }
        storage.removeValue(forKey: windowNumber)
        return nil
    }

    func activeViewModel() -> EditorViewModel? {
        viewModel(for: NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber)
    }

    func viewModel(containing url: URL) -> (windowNumber: Int, viewModel: EditorViewModel)? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL
        for (number, ref) in storage {
            guard let vm = ref.value else { continue }
            if vm.hasOpenFile(url: target) {
                return (number, vm)
            }
        }
        return nil
    }
}

private final class WindowObserverView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let onWindowChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowObserverView(frame: .zero)
        view.onWindowChange = onWindowChange
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WindowObserverView else { return }
        view.onWindowChange = onWindowChange
        DispatchQueue.main.async {
            onWindowChange(view.window)
        }
    }
}

struct WelcomeTourWindowPresenter: NSViewRepresentable {
    @Binding var isPresented: Bool
    let makeContent: () -> WelcomeTourView

    final class Coordinator: NSObject, NSWindowDelegate {
        var parent: WelcomeTourWindowPresenter
        weak var hostWindow: NSWindow?
        var window: NSWindow?

        init(parent: WelcomeTourWindowPresenter) {
            self.parent = parent
        }

        private func centerTourWindow(_ window: NSWindow) {
            guard let hostWindow else {
                window.center()
                return
            }

            let hostRect = hostWindow.contentLayoutRect
            let currentFrame = window.frame
            var targetOrigin = NSPoint(
                x: hostRect.midX - (currentFrame.width / 2),
                y: hostRect.midY - (currentFrame.height / 2)
            )

            if let screenFrame = hostWindow.screen?.visibleFrame {
                let minX = screenFrame.minX
                let maxX = screenFrame.maxX - currentFrame.width
                let minY = screenFrame.minY
                let maxY = screenFrame.maxY - currentFrame.height
                targetOrigin.x = min(max(targetOrigin.x, minX), maxX)
                targetOrigin.y = min(max(targetOrigin.y, minY), maxY)
            }

            window.setFrameOrigin(targetOrigin)
        }

        func presentIfNeeded() {
            guard window == nil else {
                if let window {
                    centerTourWindow(window)
                }
                window?.makeKeyAndOrderFront(nil)
                return
            }

            let controller = NSHostingController(rootView: parent.makeContent())
            let window = NSWindow(contentViewController: controller)
            window.title = "What\u{2019}s New"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.tabbingMode = .disallowed
            window.minSize = NSSize(width: 920, height: 680)
            window.delegate = self
            window.isMovableByWindowBackground = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = false
            window.setContentSize(NSSize(width: 980, height: 720))

            centerTourWindow(window)

            self.window = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func dismissIfNeeded() {
            guard let window else { return }
            window.close()
            self.window = nil
        }

        func windowWillClose(_ notification: Notification) {
            self.window = nil
            DispatchQueue.main.async {
                self.parent.isPresented = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            context.coordinator.hostWindow = view.window
            if isPresented {
                context.coordinator.presentIfNeeded()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.hostWindow = nsView.window
        if isPresented {
            context.coordinator.presentIfNeeded()
        } else {
            context.coordinator.dismissIfNeeded()
        }
    }
}
#endif

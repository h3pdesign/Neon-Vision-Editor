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
    static var writableContentTypes: [UTType] { [.text, .plainText, .sourceCode] }

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
                "Find in Files now supports selective project-wide replace with preview, Select All, Select None, apply, and cancel controls.",
                "Go to Line and Go to Symbol add direct in-document navigation for large files and code-heavy documents.",
                "Project sidebar rows, nested spacing, and macOS disclosure controls are more readable and easier to scan.",
                "Code Snapshot layout on macOS now keeps settings controls aligned with the composition width.",
                "CIF and mmCIF files can now open as plain-text documents."
            ],
            iconName: "sparkles.rectangle.stack",
            colors: [Color(red: 0.40, green: 0.28, blue: 0.90), Color(red: 0.96, green: 0.46, blue: 0.55)],
            toolbarItems: []
        ),
        TourPage(
            title: "Support Neon Vision Editor",
            subtitle: "Keep it free, sustainable, and improving.",
            bullets: [
                "Neon Vision Editor will always stay free to use.",
                "No subscriptions and no paywalls.",
                "Keeping the app alive still has real costs: Apple Developer Program fee, maintenance, updates, and long-term support.",
                "⭐ Optional Support Tip (Consumable) — $4.99",
                "Tip can be purchased multiple times.",
                "Your support helps cover: Apple developer fees, bug fixes and updates, future improvements and features, and long-term support.",
                "Thank you for helping keep Neon Vision Editor free for everyone."
            ],
            iconName: "heart.circle.fill",
            colors: [Color(red: 0.98, green: 0.33, blue: 0.49), Color(red: 1.00, green: 0.64, blue: 0.30)],
            toolbarItems: []
        ),
        TourPage(
            title: "A Fast, Focused Editor",
            subtitle: "Built for quick edits and flow.",
            bullets: [
                "Tabbed editing, per-file language modes, and broad syntax highlighting including TeX and LaTeX.",
                "Regex Find and Replace, Replace All, starter templates, and optional Vim workflow support.",
                "Fast loading for regular and large text files with tuned scrolling, line numbers, and highlighting refresh paths.",
                "Cross-platform Save As, Close All Tabs with confirmation, and safer unsupported-file handling.",
                "SVG, CIF, and mmCIF files open through text-focused language mappings instead of heavyweight project tooling."
            ],
            iconName: "doc.text.magnifyingglass",
            colors: [Color(red: 0.96, green: 0.48, blue: 0.28), Color(red: 0.99, green: 0.78, blue: 0.35)],
            toolbarItems: []
        ),
        TourPage(
            title: "Assistance, Themes, and Privacy",
            subtitle: "Optional help without changing the editor-first workflow.",
            bullets: [
                "Apple Intelligence integration (when available)",
                "Optional Grok, OpenAI, Gemini, and Anthropic providers",
                "AI providers are used for simple code completion and suggestions",
                "API keys stored securely in Keychain",
                "Curated built-in themes: Dracula, One Dark Pro, Nord, Tokyo Night, Gruvbox, and Neon Glow.",
                "No telemetry; external AI requests only happen when completion is enabled and a provider is selected."
            ],
            iconName: "sparkles",
            colors: [Color(red: 0.20, green: 0.55, blue: 0.95), Color(red: 0.21, green: 0.86, blue: 0.78)],
            toolbarItems: []
        ),
        TourPage(
            title: "Projects, Search, and Preview",
            subtitle: "Navigate, review, and share without leaving the editor.",
            bullets: [
                "Quick Open with Cmd+P and a background project index for large folders.",
                "Find in Files groups results and now supports selective project-wide replace with preview.",
                "Go to Line and Go to Symbol keep large document navigation direct.",
                "Project sidebar supports recursive browsing, supported-file filtering, and file actions like create, rename, duplicate, and delete.",
                "Markdown Preview includes templates, PDF export modes, copy/export actions, and an iPhone bottom sheet.",
                "Code Snapshot exports styled images from selected code for sharing and release notes."
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
                ToolbarItemInfo(title: "Save As…", description: "Save current file to a new location.", shortcutMac: "Cmd+Shift+S", shortcutPad: "Cmd+Shift+S", iconName: "square.and.arrow.down.on.square"),
                ToolbarItemInfo(title: "Close All Tabs", description: "Close all open tabs with confirmation.", shortcutMac: "None", shortcutPad: "None", iconName: "xmark.square"),
                ToolbarItemInfo(title: "Settings", description: "Settings", shortcutMac: "Cmd+,", shortcutPad: "None", iconName: "gearshape"),
                ToolbarItemInfo(title: "Insert Template", description: "Insert Template for Current Language", shortcutMac: "None", shortcutPad: "None", iconName: "doc.badge.plus"),
                ToolbarItemInfo(title: "Language", description: "Language", shortcutMac: "None", shortcutPad: "None", iconName: "textformat"),
                ToolbarItemInfo(title: "AI Model & Settings", description: "AI Model & Settings", shortcutMac: "None", shortcutPad: "None", iconName: "brain.head.profile"),
                ToolbarItemInfo(title: "Code Completion", description: "Enable Code Completion / Disable Code Completion", shortcutMac: "None", shortcutPad: "None", iconName: "bolt.horizontal.circle"),
                ToolbarItemInfo(title: "Find & Replace", description: "Find & Replace", shortcutMac: "Cmd+F", shortcutPad: "Cmd+F", iconName: "magnifyingglass"),
                ToolbarItemInfo(title: "Find in Files", description: "Search and selectively replace across the project.", shortcutMac: "Cmd+Shift+F", shortcutPad: "Cmd+Shift+F", iconName: "text.magnifyingglass"),
                ToolbarItemInfo(title: "Quick Open", description: "Open file quickly by name.", shortcutMac: "Cmd+P", shortcutPad: "Cmd+P", iconName: "magnifyingglass.circle"),
                ToolbarItemInfo(title: "Go to Line", description: "Jump directly to a line in the current file.", shortcutMac: "Cmd+L", shortcutPad: "Cmd+L", iconName: "text.line.first.and.arrowtriangle.forward"),
                ToolbarItemInfo(title: "Go to Symbol", description: "Jump to a symbol in the current document.", shortcutMac: "Cmd+Shift+J", shortcutPad: "Cmd+Shift+J", iconName: "list.bullet.indent"),
                ToolbarItemInfo(title: "Markdown Preview", description: "Toggle the Markdown preview surface.", shortcutMac: "None", shortcutPad: "None", iconName: "doc.richtext"),
                ToolbarItemInfo(title: "Preview Export", description: "Export or copy Markdown preview output.", shortcutMac: "None", shortcutPad: "None", iconName: "square.and.arrow.down"),
                ToolbarItemInfo(title: "Preview Style", description: "Choose the Markdown preview template.", shortcutMac: "None", shortcutPad: "None", iconName: "paintbrush"),
                ToolbarItemInfo(title: "Code Snapshot", description: "Create a styled image from selected code.", shortcutMac: "None", shortcutPad: "None", iconName: "camera.viewfinder"),
                ToolbarItemInfo(title: "Toggle Sidebar", description: "Toggle Sidebar", shortcutMac: "Cmd+Opt+S", shortcutPad: "Cmd+Opt+S", iconName: "sidebar.left"),
                ToolbarItemInfo(title: "Project Sidebar", description: "Toggle Project Structure Sidebar", shortcutMac: "None", shortcutPad: "Cmd+Opt+P", iconName: "sidebar.right"),
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

                if page.title == "Support Neon Vision Editor" {
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
                    Text(supportPurchaseManager.supportPurchaseButtonTitle)
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

            if supportPurchaseManager.shouldShowStoreUnavailableMessage {
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
        .task {
            await supportPurchaseManager.refreshStoreState()
        }
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
        "Neon Vision Editor will always stay free to use.",
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
                    Text("Support Neon Vision Editor")
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
                    Label(supportPurchaseManager.supportPurchaseButtonTitle, systemImage: "heart.fill")
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
            Task { await supportPurchaseManager.refreshStoreState() }
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

    private struct HelpItem: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let shortcutMac: String
        let shortcutPad: String
        let iconName: String
    }

    private struct HelpSection: Identifiable {
        let id = UUID()
        let title: String
        let iconName: String
        let items: [HelpItem]
    }

    private let sections: [HelpSection] = [
        HelpSection(
            title: "Files and Tabs",
            iconName: "doc.on.doc",
            items: [
                HelpItem(title: "New Window", description: "Open a separate editor window on macOS.", shortcutMac: "Cmd+N", shortcutPad: "None", iconName: "macwindow.badge.plus"),
                HelpItem(title: "New Tab", description: "Create a new tab in the current editor window.", shortcutMac: "Cmd+T", shortcutPad: "Cmd+T", iconName: "plus.square.on.square"),
                HelpItem(title: "Open File", description: "Choose a local text or code file and open it in the editor.", shortcutMac: "Cmd+O", shortcutPad: "Cmd+O", iconName: "folder"),
                HelpItem(title: "Save File", description: "Write the current tab back to its file.", shortcutMac: "Cmd+S", shortcutPad: "Cmd+S", iconName: "square.and.arrow.down"),
                HelpItem(title: "Save As", description: "Save the current tab to a new location.", shortcutMac: "Cmd+Shift+S", shortcutPad: "Cmd+Shift+S", iconName: "square.and.arrow.down.on.square"),
                HelpItem(title: "Close All Tabs", description: "Close every open tab with confirmation.", shortcutMac: "None", shortcutPad: "None", iconName: "xmark.square")
            ]
        ),
        HelpSection(
            title: "Editing",
            iconName: "pencil.and.scribble",
            items: [
                HelpItem(title: "Undo", description: "Undo the latest editor change.", shortcutMac: "Cmd+Z", shortcutPad: "Cmd+Z", iconName: "arrow.uturn.backward"),
                HelpItem(title: "Clear Editor", description: "Remove the current editor contents after confirmation.", shortcutMac: "None", shortcutPad: "None", iconName: "eraser"),
                HelpItem(title: "Insert Template", description: "Insert a starter snippet for the selected language.", shortcutMac: "None", shortcutPad: "None", iconName: "doc.badge.plus"),
                HelpItem(title: "Line Wrap", description: "Toggle soft wrapping for long lines.", shortcutMac: "Cmd+Opt+L", shortcutPad: "Cmd+Opt+L", iconName: "text.justify"),
                HelpItem(title: "Font Smaller", description: "Decrease the editor font size.", shortcutMac: "None", shortcutPad: "None", iconName: "textformat.size.smaller"),
                HelpItem(title: "Font Larger", description: "Increase the editor font size.", shortcutMac: "None", shortcutPad: "None", iconName: "textformat.size.larger")
            ]
        ),
        HelpSection(
            title: "Navigation and Search",
            iconName: "magnifyingglass",
            items: [
                HelpItem(title: "Find and Replace", description: "Search or replace text in the current file.", shortcutMac: "Cmd+F", shortcutPad: "Cmd+F", iconName: "magnifyingglass"),
                HelpItem(title: "Find in Files", description: "Search the project and selectively replace matches.", shortcutMac: "Cmd+Shift+F", shortcutPad: "Cmd+Shift+F", iconName: "text.magnifyingglass"),
                HelpItem(title: "Quick Open", description: "Open project files quickly by name.", shortcutMac: "Cmd+P", shortcutPad: "Cmd+P", iconName: "magnifyingglass.circle"),
                HelpItem(title: "Go to Line", description: "Jump to a specific line in the current document.", shortcutMac: "Cmd+L", shortcutPad: "Cmd+L", iconName: "text.line.first.and.arrowtriangle.forward"),
                HelpItem(title: "Go to Symbol", description: "Jump to a symbol discovered in the current document.", shortcutMac: "Cmd+Shift+J", shortcutPad: "Cmd+Shift+J", iconName: "list.bullet.indent")
            ]
        ),
        HelpSection(
            title: "Sidebars and Project",
            iconName: "sidebar.left",
            items: [
                HelpItem(title: "Toggle Sidebar", description: "Show or hide the document outline/sidebar area.", shortcutMac: "Cmd+Opt+S", shortcutPad: "Cmd+Opt+S", iconName: "sidebar.left"),
                HelpItem(title: "Project Sidebar", description: "Show the project tree for folders, files, and project actions.", shortcutMac: "None", shortcutPad: "Cmd+Opt+P", iconName: "sidebar.right"),
                HelpItem(title: "Language", description: "Change the syntax language for highlighting and templates.", shortcutMac: "Cmd+Shift+L", shortcutPad: "Cmd+Shift+L", iconName: "textformat")
            ]
        ),
        HelpSection(
            title: "Preview, Export, and Compare",
            iconName: "doc.richtext",
            items: [
                HelpItem(title: "Markdown Preview", description: "Toggle the rendered Markdown preview for Markdown files.", shortcutMac: "None", shortcutPad: "None", iconName: "doc.richtext"),
                HelpItem(title: "Preview Export", description: "Copy or export Markdown preview output, including PDF modes.", shortcutMac: "None", shortcutPad: "None", iconName: "square.and.arrow.down"),
                HelpItem(title: "Preview Style", description: "Choose the Markdown preview template.", shortcutMac: "None", shortcutPad: "None", iconName: "paintbrush"),
                HelpItem(title: "Code Snapshot", description: "Create a styled image from selected code.", shortcutMac: "None", shortcutPad: "None", iconName: "camera.viewfinder"),
                HelpItem(title: "Compare with Disk", description: "Compare the current tab with the file on disk.", shortcutMac: "None", shortcutPad: "None", iconName: "doc.text.magnifyingglass"),
                HelpItem(title: "Compare Open Tabs", description: "Compare two currently open tabs.", shortcutMac: "None", shortcutPad: "None", iconName: "rectangle.split.2x1")
            ]
        ),
        HelpSection(
            title: "Assistance and Modes",
            iconName: "sparkles",
            items: [
                HelpItem(title: "AI Model and Settings", description: "Open provider and model settings for AI assistance.", shortcutMac: "None", shortcutPad: "None", iconName: "brain.head.profile"),
                HelpItem(title: "Code Completion", description: "Enable or disable AI-assisted completion.", shortcutMac: "None", shortcutPad: "None", iconName: "bolt.horizontal.circle"),
                HelpItem(title: "Performance Mode", description: "Force large-file performance behavior for the current document.", shortcutMac: "None", shortcutPad: "None", iconName: "speedometer"),
                HelpItem(title: "Brain Dump Mode", description: "Switch to a distraction-light writing mode.", shortcutMac: "None", shortcutPad: "None", iconName: "note.text"),
                HelpItem(title: "Keyboard Snippet Bar", description: "Show or hide the iPhone/iPad keyboard helper bar.", shortcutMac: "None", shortcutPad: "None", iconName: "keyboard.chevron.compact.down"),
                HelpItem(title: "Hide Keyboard", description: "Dismiss the on-screen keyboard on iPhone and iPad.", shortcutMac: "None", shortcutPad: "None", iconName: "keyboard.chevron.compact.down")
            ]
        ),
        HelpSection(
            title: "App Controls",
            iconName: "gearshape",
            items: [
                HelpItem(title: "Settings", description: "Open app settings and support options.", shortcutMac: "Cmd+,", shortcutPad: "None", iconName: "gearshape"),
                HelpItem(title: "Toolbar Help", description: "Open this toolbar reference.", shortcutMac: "Cmd+?", shortcutPad: "Cmd+?", iconName: "questionmark.circle"),
                HelpItem(title: "Welcome Tour", description: "Show the onboarding tour and release overview.", shortcutMac: "None", shortcutPad: "None", iconName: "sparkles.rectangle.stack"),
                HelpItem(title: "Translucent Window", description: "Toggle translucent window styling where supported.", shortcutMac: "None", shortcutPad: "None", iconName: "rectangle"),
                HelpItem(title: "Blue Toolbar Icons", description: "Switch iPhone toolbar icons between blue and neutral styling.", shortcutMac: "None", shortcutPad: "None", iconName: "checkmark.circle.fill"),
                HelpItem(title: "Updates", description: "Check for app updates in direct-distribution builds.", shortcutMac: "None", shortcutPad: "None", iconName: "arrow.triangle.2.circlepath.circle"),
                HelpItem(title: "Bracket Helper Bar", description: "Show or hide the macOS bracket helper bar.", shortcutMac: "None", shortcutPad: "None", iconName: "curlybraces")
            ]
        )
    ]

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let compact = proxy.size.width < 560
                let cardMinimumWidth = compact ? max(240, proxy.size.width - 40) : CGFloat(300)
                let columns = [GridItem(.adaptive(minimum: cardMinimumWidth), spacing: 12, alignment: .top)]

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: compact ? 18 : 22) {
                        header(compact: compact)

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                sectionHeader(section)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                    ForEach(section.items) { item in
                                        helpCard(item, compact: compact)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(compact ? 16 : 24)
                }
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

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: compact ? 30 : 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Toolbar Help")
                        .font(.system(size: compact ? 27 : 34, weight: .bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)
                    Text("Every toolbar symbol, what it does, and the fastest shortcut where available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(_ section: HelpSection) -> some View {
        Label(section.title, systemImage: section.iconName)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.isHeader)
    }

    private func helpCard(_ item: HelpItem, compact: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12))
                Image(systemName: item.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.medium)
            }
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 7) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.description)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)

                if compact {
                    VStack(alignment: .leading, spacing: 6) {
                        shortcutCapsule("macOS", value: item.shortcutMac)
                        shortcutCapsule("iPad", value: item.shortcutPad)
                    }
                } else {
                    HStack(spacing: 6) {
                        shortcutCapsule("macOS", value: item.shortcutMac)
                        shortcutCapsule("iPad", value: item.shortcutPad)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: compact ? 132 : 124, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.description). macOS shortcut: \(item.shortcutMac). iPad shortcut: \(item.shortcutPad).")
    }

    private func shortcutCapsule(_ label: String, value: String) -> some View {
        let displayText = value.isEmpty ? label : "\(label): \(value)"
        return Text(displayText)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
            )
            .accessibilityLabel(displayText)
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
    static let compareCurrentTabAgainstDiskRequested = Notification.Name("compareCurrentTabAgainstDiskRequested")
    static let compareOpenTabsRequested = Notification.Name("compareOpenTabsRequested")
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

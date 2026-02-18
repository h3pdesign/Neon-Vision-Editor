import SwiftUI
import Foundation
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
    @Binding var statusMessage: String
    var onFindNext: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
    @AppStorage("SettingsLiquidGlassEnabled") private var liquidGlassEnabled: Bool = true
    @FocusState private var findFieldFocused: Bool

    private var shouldUsePanelGlass: Bool {
        translucentWindow && liquidGlassEnabled && !reduceTransparency
    }

    var body: some View {
        GlassSurface(
            enabled: shouldUsePanelGlass,
            material: colorScheme == .dark ? .regularMaterial : .ultraThinMaterial,
            fallbackColor: Color.secondary.opacity(0.12),
            shape: .rounded(14)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Find & Replace").font(.headline)
                LabeledContent("Find") {
                    TextField("Search text", text: $findQuery)
                        .textFieldStyle(.roundedBorder)
                        .focused($findFieldFocused)
                        .onSubmit { onFindNext() }
                }
                LabeledContent("Replace") {
                    TextField("Replacement", text: $replaceQuery)
                        .textFieldStyle(.roundedBorder)
                }
                Toggle("Use Regex", isOn: $useRegex)
                Toggle("Case Sensitive", isOn: $caseSensitive)
                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button("Find Next") { onFindNext() }
                    Button("Replace") { onReplace() }.disabled(findQuery.isEmpty)
                    Button("Replace All") { onReplaceAll() }.disabled(findQuery.isEmpty)
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
            .padding(16)
            .frame(minWidth: 380)
        }
        .onAppear {
            findFieldFocused = true
        }
    }
}

struct QuickFileSwitcherPanel: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
    }

    @Binding var query: String
    let items: [Item]
    let onSelect: (Item) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
    @AppStorage("SettingsLiquidGlassEnabled") private var liquidGlassEnabled: Bool = true

    private var shouldUsePanelGlass: Bool {
        translucentWindow && liquidGlassEnabled && !reduceTransparency
    }

    var body: some View {
        GlassSurface(
            enabled: shouldUsePanelGlass,
            material: colorScheme == .dark ? .regularMaterial : .ultraThinMaterial,
            fallbackColor: Color.secondary.opacity(0.12),
            shape: .rounded(14)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Open")
                    .font(.headline)
                TextField("Search files and tabs", text: $query)
                    .textFieldStyle(.roundedBorder)

                List(items) { item in
                    Button {
                        onSelect(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)

                HStack {
                    Text("\(items.count) results")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Close") { dismiss() }
                }
            }
            .padding(16)
            .frame(minWidth: 520, minHeight: 380)
        }
    }
}

struct WelcomeTourView: View {
    @Environment(\.colorScheme) private var colorScheme
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
            subtitle: "Major changes since v0.4.25:",
            bullets: [
                "Added a dedicated macOS translucency strength setting (`Light`, `Medium`, `Strong`) without changing the existing translucency toggle behavior.",
                "Improved iOS Settings navigation order by placing `More` before `AI` and defaulting the `More` page to `Support` first.",
                "Improved macOS translucency consistency by keeping window chrome layout stable when toggling translucency.",
                "Fixed macOS release/preflight build failures by including the shared `GlassSurface` UI component in tracked project sources."
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
                "⭐ One-time Support Purchase — $4.99",
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
                "iPad hardware-keyboard shortcuts are shown where supported; no shortcut? the toolbar is the fastest path",
                "iOS quick start: open files first, use the `...` menu for all secondary actions, and optionally enable the bottom action bar in Settings → Editor"
            ],
            iconName: "slider.horizontal.3",
            colors: [Color(red: 0.36, green: 0.32, blue: 0.92), Color(red: 0.92, green: 0.49, blue: 0.64)],
            toolbarItems: [
                ToolbarItemInfo(title: "New Window", description: "New Window", shortcutMac: "Cmd+N", shortcutPad: "None", iconName: "macwindow.badge.plus"),
                ToolbarItemInfo(title: "New Tab", description: "New Tab", shortcutMac: "Cmd+T", shortcutPad: "Cmd+T", iconName: "plus.square.on.square"),
                ToolbarItemInfo(title: "Open File…", description: "Open File…", shortcutMac: "Cmd+O", shortcutPad: "Cmd+O", iconName: "folder"),
                ToolbarItemInfo(title: "Save File", description: "Save File", shortcutMac: "Cmd+S", shortcutPad: "Cmd+S", iconName: "square.and.arrow.down"),
                ToolbarItemInfo(title: "Insert Template", description: "Insert Template for Current Language", shortcutMac: "None", shortcutPad: "None", iconName: "doc.badge.plus"),
                ToolbarItemInfo(title: "Language", description: "Language", shortcutMac: "None", shortcutPad: "None", iconName: "textformat"),
                ToolbarItemInfo(title: "AI Model & Settings", description: "AI Model & Settings", shortcutMac: "None", shortcutPad: "None", iconName: "brain.head.profile"),
                ToolbarItemInfo(title: "Code Completion", description: "Enable Code Completion / Disable Code Completion", shortcutMac: "None", shortcutPad: "None", iconName: "bolt.horizontal.circle"),
                ToolbarItemInfo(title: "Find & Replace", description: "Find & Replace", shortcutMac: "Cmd+F", shortcutPad: "Cmd+F", iconName: "magnifyingglass"),
                ToolbarItemInfo(title: "Toggle Sidebar", description: "Toggle Sidebar", shortcutMac: "Cmd+Opt+S", shortcutPad: "Cmd+Opt+S", iconName: "sidebar.left"),
                ToolbarItemInfo(title: "Project Sidebar", description: "Toggle Project Structure Sidebar", shortcutMac: "None", shortcutPad: "None", iconName: "sidebar.right"),
                ToolbarItemInfo(title: "Line Wrap", description: "Enable Wrap / Disable Wrap", shortcutMac: "Cmd+Opt+L", shortcutPad: "Cmd+Opt+L", iconName: "text.justify"),
                ToolbarItemInfo(title: "Clear Editor", description: "Clear Editor", shortcutMac: "None", shortcutPad: "None", iconName: "trash"),
                ToolbarItemInfo(title: "More Actions", description: "Open the three-dot menu for secondary actions", shortcutMac: "None", shortcutPad: "None", iconName: "ellipsis.circle"),
                ToolbarItemInfo(title: "Bottom Action Bar", description: "Optional iOS quick actions row (Settings → Editor)", shortcutMac: "None", shortcutPad: "None", iconName: "rectangle.bottomthird.inset.filled")
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

                if page.title == "Toolbar Map" && page.bullets.count >= 2 {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            bulletRow(page.bullets[0])
                            Text("scroll for viewing all toolbar options.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        bulletRow(page.bullets[1])
                    }
                    .padding(.bottom, 0)
                } else {
                    ForEach(page.bullets, id: \.self) { bullet in
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
            if supportPurchaseManager.hasSupported {
                Label("Thank you for your support.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14, weight: .semibold))
            }

            Button {
                Task { await supportPurchaseManager.purchaseSupport() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                    Text("Support with One-Time Purchase — \(supportPurchaseManager.supportPriceLabel)")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                supportPurchaseManager.isPurchasing
                || supportPurchaseManager.isLoadingProducts
                || !supportPurchaseManager.canUseInAppPurchases
            )

            if let status = supportPurchaseManager.statusMessage, !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !supportPurchaseManager.canUseInAppPurchases {
                Text("Purchase is available in App Store/TestFlight builds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        )
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

extension Notification.Name {
    static let moveCursorToLine = Notification.Name("moveCursorToLine")
    static let caretPositionDidChange = Notification.Name("caretPositionDidChange")
    static let pastedText = Notification.Name("pastedText")
    static let toggleTranslucencyRequested = Notification.Name("toggleTranslucencyRequested")
    static let clearEditorRequested = Notification.Name("clearEditorRequested")
    static let showFindReplaceRequested = Notification.Name("showFindReplaceRequested")
    static let toggleProjectStructureSidebarRequested = Notification.Name("toggleProjectStructureSidebarRequested")
    static let showAPISettingsRequested = Notification.Name("showAPISettingsRequested")
    static let selectAIModelRequested = Notification.Name("selectAIModelRequested")
    static let showQuickSwitcherRequested = Notification.Name("showQuickSwitcherRequested")
    static let showWelcomeTourRequested = Notification.Name("showWelcomeTourRequested")
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
    static let whitespaceScalarInspectionResult = Notification.Name("whitespaceScalarInspectionResult")
    static let showUpdaterRequested = Notification.Name("showUpdaterRequested")
}

extension NSRange {
    func toOptional() -> NSRange? { self.location == NSNotFound ? nil : self }
}

enum EditorCommandUserInfo {
    static let windowNumber = "targetWindowNumber"
    static let inspectionMessage = "inspectionMessage"
    static let rangeLocation = "rangeLocation"
    static let rangeLength = "rangeLength"
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
#endif

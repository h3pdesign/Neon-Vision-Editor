import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

extension ContentView {
    private var compactActiveProviderName: String {
        activeProviderName.components(separatedBy: " (").first ?? activeProviderName
    }

#if os(iOS)
    private var isIPadToolbarLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var iPadToolbarMaxWidth: CGFloat {
        let screenWidth = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .screen.bounds.width ?? 1024
        let target = screenWidth * 0.72
        return min(max(target, 560), 980)
    }

    private var iPadPromotedActionsCount: Int {
        switch iPadToolbarMaxWidth {
        case 920...: return 7
        case 840...: return 6
        case 760...: return 5
        case 680...: return 4
        case 620...: return 3
        default: return 2
        }
    }

    @ViewBuilder
    private var newTabControl: some View {
        Button(action: { viewModel.addNewTab() }) {
            Image(systemName: "plus.square.on.square")
        }
        .help("New Tab (Cmd+T)")
    }

    @ViewBuilder
    private var settingsControl: some View {
        Button(action: { showSettingsSheet = true }) {
            Image(systemName: "gearshape")
        }
        .help("Settings (Cmd+,)")
    }

    @ViewBuilder
    private var languagePickerControl: some View {
        Picker("Language", selection: currentLanguagePickerBinding) {
            ForEach(["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"], id: \.self) { lang in
                let label: String = {
                    switch lang {
                    case "php": return "PHP"
                    case "cobol": return "COBOL"
                    case "dotenv": return "Dotenv"
                    case "proto": return "Proto"
                    case "graphql": return "GraphQL"
                    case "rst": return "reStructuredText"
                    case "nginx": return "Nginx"
                    case "objective-c": return "Objective-C"
                    case "csharp": return "C#"
                    case "c": return "C"
                    case "cpp": return "C++"
                    case "json": return "JSON"
                    case "xml": return "XML"
                    case "yaml": return "YAML"
                    case "toml": return "TOML"
                    case "csv": return "CSV"
                    case "ini": return "INI"
                    case "sql": return "SQL"
                    case "vim": return "Vim"
                    case "log": return "Log"
                    case "ipynb": return "Jupyter Notebook"
                    case "html": return "HTML"
                    case "expressionengine": return "ExpressionEngine"
                    case "css": return "CSS"
                    case "standard": return "Standard"
                    default: return lang.capitalized
                    }
                }()
                Text(label).tag(lang)
            }
        }
        .labelsHidden()
        .help("Language")
        .frame(width: isIPadToolbarLayout ? 160 : 120)
    }

    @ViewBuilder
    private var activeProviderBadgeControl: some View {
        Text(compactActiveProviderName)
            .font(.caption)
            .foregroundColor(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .help("Active provider")
    }

    @ViewBuilder
    private var clearEditorControl: some View {
        Button(action: {
            requestClearEditorContent()
        }) {
            Image(systemName: "trash")
        }
        .help("Clear Editor")
    }

    @ViewBuilder
    private var insertTemplateControl: some View {
        Button(action: { insertTemplateForCurrentLanguage() }) {
            Image(systemName: "doc.badge.plus")
        }
        .help("Insert Template for Current Language")
    }

    @ViewBuilder
    private var openFileControl: some View {
        Button(action: { openFileFromToolbar() }) {
            Image(systemName: "folder")
        }
        .help("Open File… (Cmd+O)")
    }

    @ViewBuilder
    private var saveFileControl: some View {
        Button(action: { saveCurrentTabFromToolbar() }) {
            Image(systemName: "square.and.arrow.down")
        }
        .disabled(viewModel.selectedTab == nil)
        .help("Save File (Cmd+S)")
    }

    @ViewBuilder
    private var toggleSidebarControl: some View {
        Button(action: { toggleSidebarFromToolbar() }) {
            Image(systemName: "sidebar.left")
        }
        .help("Toggle Sidebar (Cmd+Opt+S)")
    }

    @ViewBuilder
    private var toggleProjectSidebarControl: some View {
        Button(action: { showProjectStructureSidebar.toggle() }) {
            Image(systemName: "sidebar.right")
        }
        .help("Toggle Project Structure Sidebar")
    }

    @ViewBuilder
    private var findReplaceControl: some View {
        Button(action: { showFindReplace = true }) {
            Image(systemName: "magnifyingglass")
        }
        .help("Find & Replace (Cmd+F)")
    }

    @ViewBuilder
    private var iPadPromotedActions: some View {
        if iPadPromotedActionsCount >= 1 { openFileControl }
        if iPadPromotedActionsCount >= 2 { saveFileControl }
        if iPadPromotedActionsCount >= 3 { toggleSidebarControl }
        if iPadPromotedActionsCount >= 4 { toggleProjectSidebarControl }
        if iPadPromotedActionsCount >= 5 { findReplaceControl }
    }

    @ViewBuilder
    private var moreActionsControl: some View {
        Menu {
            Button(action: { insertTemplateForCurrentLanguage() }) {
                Label("Insert Template", systemImage: "doc.badge.plus")
            }

            Button(action: { openFileFromToolbar() }) {
                Label("Open File…", systemImage: "folder")
            }

            Button(action: { saveCurrentTabFromToolbar() }) {
                Label("Save File", systemImage: "square.and.arrow.down")
            }
            .disabled(viewModel.selectedTab == nil)

            Button(action: { toggleSidebarFromToolbar() }) {
                Label("Toggle Sidebar", systemImage: "sidebar.left")
            }

            Button(action: { showProjectStructureSidebar.toggle() }) {
                Label("Toggle Project Structure Sidebar", systemImage: "sidebar.right")
            }

            Button(action: { showFindReplace = true }) {
                Label("Find & Replace", systemImage: "magnifyingglass")
            }

            Button(action: {
                viewModel.isBrainDumpMode.toggle()
                UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
            }) {
                Label("Brain Dump Mode", systemImage: "note.text")
            }
            
            Button(action: {
                showWelcomeTour = true
            }) {
                Label("Welcome Tour", systemImage: "sparkles.rectangle.stack")
            }

            Button(action: {
                enableTranslucentWindow.toggle()
                UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
            }) {
                Label("Translucent Window Background", systemImage: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
            }

        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .help("More Actions")
    }

    @ViewBuilder
    private var iOSToolbarControls: some View {
        languagePickerControl
        newTabControl
        activeProviderBadgeControl
        clearEditorControl
        settingsControl
        moreActionsControl
    }

    @ViewBuilder
    private var iPadDistributedToolbarControls: some View {
        activeProviderBadgeControl
        languagePickerControl
        newTabControl
        Spacer(minLength: 18)
        iPadPromotedActions
        Spacer(minLength: 18)
        clearEditorControl
        settingsControl
        moreActionsControl
    }
#endif
    @ToolbarContentBuilder
    var editorToolbarContent: some ToolbarContent {
#if os(iOS)
        ToolbarItemGroup(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                if isIPadToolbarLayout {
                    iPadDistributedToolbarControls
                } else {
                    iOSToolbarControls
                }
            }
            .frame(maxWidth: isIPadToolbarLayout ? iPadToolbarMaxWidth : .infinity, alignment: .trailing)
        }
#else
        ToolbarItemGroup(placement: .automatic) {
            Picker("Language", selection: currentLanguagePickerBinding) {
                ForEach(["swift", "python", "javascript", "typescript", "php", "java", "kotlin", "go", "ruby", "rust", "cobol", "dotenv", "proto", "graphql", "rst", "nginx", "sql", "html", "expressionengine", "css", "c", "cpp", "csharp", "objective-c", "json", "xml", "yaml", "toml", "csv", "ini", "vim", "log", "ipynb", "markdown", "bash", "zsh", "powershell", "standard", "plain"], id: \.self) { lang in
                    let label: String = {
                        switch lang {
                        case "php": return "PHP"
                        case "cobol": return "COBOL"
                        case "dotenv": return "Dotenv"
                        case "proto": return "Proto"
                        case "graphql": return "GraphQL"
                        case "rst": return "reStructuredText"
                        case "nginx": return "Nginx"
                        case "objective-c": return "Objective‑C"
                        case "csharp": return "C#"
                        case "c": return "C"
                        case "cpp": return "C++"
                        case "json": return "JSON"
                        case "xml": return "XML"
                        case "yaml": return "YAML"
                        case "toml": return "TOML"
                        case "csv": return "CSV"
                        case "ini": return "INI"
                        case "sql": return "SQL"
                        case "vim": return "Vim"
                        case "log": return "Log"
                        case "ipynb": return "Jupyter Notebook"
                        case "html": return "HTML"
                        case "expressionengine": return "ExpressionEngine"
                        case "css": return "CSS"
                        case "standard": return "Standard"
                        default: return lang.capitalized
                        }
                    }()
                    Text(label).tag(lang)
                }
            }
            .labelsHidden()
            .help("Language")
            .controlSize(.large)
            .frame(width: 140)
            .padding(.vertical, 2)

            Text(compactActiveProviderName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.9)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .padding(.leading, 6)
                .help("Active provider")

            Button(action: {
                openSettings()
            }) {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Button(action: { adjustEditorFontSize(-1) }) {
                Image(systemName: "textformat.size.smaller")
            }
            .help("Decrease Font Size")

            Button(action: { adjustEditorFontSize(1) }) {
                Image(systemName: "textformat.size.larger")
            }
            .help("Increase Font Size")

            Button(action: {
                requestClearEditorContent()
            }) {
                Image(systemName: "trash")
            }
            .help("Clear Editor")

            Button(action: {
                insertTemplateForCurrentLanguage()
            }) {
                Image(systemName: "doc.badge.plus")
            }
            .help("Insert Template for Current Language")

            Button(action: { openFileFromToolbar() }) {
                Image(systemName: "folder")
            }
        .help("Open File… (Cmd+O)")

            Button(action: { viewModel.addNewTab() }) {
                Image(systemName: "plus.square.on.square")
            }
        .help("New Tab (Cmd+T)")

            #if os(macOS)
            Button(action: {
                openWindow(id: "blank-window")
            }) {
                Image(systemName: "macwindow.badge.plus")
            }
            .help("New Window (Cmd+N)")
            #endif

            Button(action: {
                saveCurrentTabFromToolbar()
            }) {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(viewModel.selectedTab == nil)
            .help("Save File (Cmd+S)")

            Button(action: {
                toggleSidebarFromToolbar()
            }) {
                Image(systemName: "sidebar.left")
                    .symbolVariant(viewModel.showSidebar ? .fill : .none)
            }
            .help("Toggle Sidebar (Cmd+Opt+S)")

            Button(action: {
                showProjectStructureSidebar.toggle()
            }) {
                Image(systemName: "sidebar.right")
                    .symbolVariant(showProjectStructureSidebar ? .fill : .none)
            }
            .help("Toggle Project Structure Sidebar")

            Button(action: {
                showFindReplace = true
            }) {
                Image(systemName: "magnifyingglass")
            }
            .help("Find & Replace (Cmd+F)")

            Button(action: {
                viewModel.isBrainDumpMode.toggle()
                UserDefaults.standard.set(viewModel.isBrainDumpMode, forKey: "BrainDumpModeEnabled")
            }) {
                Image(systemName: viewModel.isBrainDumpMode ? "note.text" : "note.text")
                    .symbolVariant(viewModel.isBrainDumpMode ? .fill : .none)
            }
            .help("Brain Dump Mode")
            .accessibilityLabel("Brain Dump Mode")

            Button(action: {
                enableTranslucentWindow.toggle()
                UserDefaults.standard.set(enableTranslucentWindow, forKey: "EnableTranslucentWindow")
                NotificationCenter.default.post(name: .toggleTranslucencyRequested, object: enableTranslucentWindow)
            }) {
                Image(systemName: enableTranslucentWindow ? "rectangle.fill" : "rectangle")
            }
            .help("Toggle Translucent Window Background")
            .accessibilityLabel("Translucent Window Background")

        }
#endif
    }
}

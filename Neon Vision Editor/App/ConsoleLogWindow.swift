import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ConsoleLogWindow: View {
    @ObservedObject var logger = AppLogger.shared
    @State private var searchText = ""
    @State private var selectedLevel: LogEntry.LogLevel? = nil
    @State private var autoScroll = true
    @State private var showTimestamps = true
    @State private var showIcons = true
    
    private var filteredEntries: [LogEntry] {
        var entries = logger.entries
        
        // Filter by level
        if let level = selectedLevel {
            entries = entries.filter { $0.level == level }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return entries
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 12) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
#if os(macOS)
                .background(Color(nsColor: .textBackgroundColor))
#else
                .background(Color(.systemBackground))
#endif
                .cornerRadius(6)
                .frame(maxWidth: 300)
                
                Divider()
                    .frame(height: 20)
                
                // Level filter
                Picker("Level", selection: $selectedLevel) {
                    Text("All Levels").tag(nil as LogEntry.LogLevel?)
                    Divider()
                    ForEach(LogEntry.LogLevel.allCases, id: \.self) { level in
                        HStack {
                            Image(systemName: level.icon)
                            Text(level.rawValue)
                        }
                        .tag(level as LogEntry.LogLevel?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                
                Divider()
                    .frame(height: 20)
                
                // Options
                Toggle(isOn: $showTimestamps) {
                    Image(systemName: "clock")
                }
                .help("Show Timestamps")
                .toggleStyle(.button)
                
                Toggle(isOn: $showIcons) {
                    Image(systemName: "star.circle")
                }
                .help("Show Icons")
                .toggleStyle(.button)
                
                Toggle(isOn: $autoScroll) {
                    Image(systemName: "arrow.down.to.line")
                }
                .help("Auto-scroll to Bottom")
                .toggleStyle(.button)
                
                Spacer()
                
                // Stats
                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                    .frame(height: 20)
                
                // Clear button
                Button(action: {
                    logger.clear()
                }) {
                    Image(systemName: "trash")
                }
                .help("Clear All Logs")
                
                // Export button
                Button(action: exportLogs) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export Logs")
            }
            .padding(8)
#if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
#else
            .background(Color(.systemBackground))
#endif
            
            Divider()
            
            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            LogEntryRow(
                                entry: entry,
                                showTimestamp: showTimestamps,
                                showIcon: showIcons
                            )
                            .id(entry.id)
                            
                            Divider()
                        }
                    }
                }
                .onChange(of: filteredEntries.count) { _, _ in
                    if autoScroll, let lastEntry = filteredEntries.last {
                        withAnimation {
                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Empty state
            if filteredEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(searchText.isEmpty ? "No log entries yet" : "No matching entries")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    if !searchText.isEmpty {
                        Text("Try adjusting your search or filters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
    
    private func exportLogs() {
#if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "console-log-\(Date().ISO8601Format()).txt"
        panel.canCreateDirectories = true
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            let logText = filteredEntries.map { entry in
                "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
            }.joined(separator: "\n")
            
            try? logText.write(to: url, atomically: true, encoding: .utf8)
        }
#endif
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    let showTimestamp: Bool
    let showIcon: Bool
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showIcon {
                Image(systemName: entry.level.icon)
                    .foregroundColor(entry.level.color)
                    .frame(width: 16)
            }
            
            if showTimestamp {
                Text(entry.formattedTimestamp)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 85, alignment: .leading)
            }
            
            Text(entry.category)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
                .frame(minWidth: 80, alignment: .leading)
            
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(entry.level.color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isHovering ? Color.secondary.opacity(0.06) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
#if os(macOS)
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
            
            Button("Copy Full Entry") {
                let text = "[\(entry.formattedTimestamp)] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
#endif
    }
}

#if os(macOS)
import AppKit
#endif

struct ConsoleLogWindow_Previews: PreviewProvider {
    static var previews: some View {
        ConsoleLogWindow()
            .onAppear {
                // Add sample logs for preview
                let logger = AppLogger.shared
                logger.info("Application started", category: "App")
                logger.debug("Loading configuration", category: "Config")
                logger.info("Using Anthropic AI model", category: "AI")
                logger.warning("API rate limit approaching", category: "AI")
                logger.error("Failed to connect to API", category: "Network")
                logger.info("File opened: example.swift", category: "Editor")
            }
    }
}

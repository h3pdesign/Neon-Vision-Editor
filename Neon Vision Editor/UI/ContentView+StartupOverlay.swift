import SwiftUI

extension ContentView {
    var sharedImportItems: [SharedImportStore.Item] {
        guard sharedImportAccessAllowed else { return [] }
        _ = sharedImportsRefreshToken
        return SharedImportStore.items(limit: 5)
    }

    var shareImportsAutoOpenEnabled: Bool {
        UserDefaults.standard.object(forKey: "SettingsShareImportsAutoOpen") as? Bool ?? true
    }

    var sharedImportDestinationMessage: String {
        let count = pendingSharedImportURLs.count
        if count == 1, let name = pendingSharedImportURLs.first?.lastPathComponent {
            return "Choose where to open \(name)."
        }
        return "Choose where to open \(count) shared items."
    }

    var sharedImportOpenNewTabsTitle: String {
        pendingSharedImportURLs.count == 1 ? "Open in New Tab" : "Open in New Tabs"
    }

    var canReplaceCurrentTabWithPendingSharedImport: Bool {
        guard pendingSharedImportURLs.count == 1,
              let tab = viewModel.selectedTab,
              !tab.isLoadingContent,
              tab.isReadOnlyPreview != true else {
            return false
        }
        return true
    }

    var startupRecentFiles: [RecentFilesStore.Item] {
        _ = recentFilesRefreshToken
        return RecentFilesStore.items(limit: 5)
    }

    var shouldShowStartupRecentFilesCard: Bool {
        guard !brainDumpLayoutEnabled else { return false }
        guard viewModel.tabs.count == 1 else { return false }
        guard let tab = viewModel.selectedTab else { return false }
        guard !tab.isLoadingContent else { return false }
        guard tab.fileURL == nil else { return false }
        guard tab.content.isEmpty else { return false }
        return !startupRecentFiles.isEmpty || !sharedImportItems.isEmpty
    }

    var shouldShowSafeModeStartupCard: Bool {
        guard startupBehavior == .safeMode else { return false }
        guard !brainDumpLayoutEnabled else { return false }
        guard viewModel.tabs.count == 1 else { return false }
        guard let tab = viewModel.selectedTab else { return false }
        guard !tab.isLoadingContent else { return false }
        return tab.fileURL == nil
    }

    var shouldShowStartupOverlay: Bool {
        shouldShowSafeModeStartupCard || shouldShowStartupRecentFilesCard || !draftRecoveryCandidates.isEmpty
    }

    @ViewBuilder
    var startupOverlay: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowSafeModeStartupCard {
                safeModeStartupCard
            }
            if !draftRecoveryCandidates.isEmpty {
                draftRecoveryCard
            }
            if shouldShowStartupRecentFilesCard {
                if !sharedImportItems.isEmpty {
                    startupSharedImportsCard
                }
                if !startupRecentFiles.isEmpty {
                    startupRecentFilesCard
                }
            }
        }
        .padding(24)
    }

    var draftRecoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recover Unsaved Drafts", systemImage: "arrow.counterclockwise")
                .font(.headline)

            Text("Choose the drafts to restore from the previous session.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(draftRecoveryCandidates) { candidate in
                        Toggle(isOn: Binding(
                            get: { selectedDraftRecoveryCandidateIDs.contains(candidate.id) },
                            set: { isSelected in
                                if isSelected {
                                    selectedDraftRecoveryCandidateIDs.insert(candidate.id)
                                } else {
                                    selectedDraftRecoveryCandidateIDs.remove(candidate.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.snapshot.name)
                                    .lineLimit(1)
                                Text(candidate.snapshot.language)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)

            HStack(spacing: 12) {
                Button("Restore Selected") {
                    restoreSelectedDraftRecoveryCandidates()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDraftRecoveryCandidateIDs.isEmpty)

                Button("Discard Drafts", role: .destructive) {
                    discardUnsavedDraftRecoveryCandidates()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unsaved draft recovery")
    }

    var safeModeStartupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safe Mode", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.orange)

            Text(safeModeMessage ?? "Safe Mode is active for this launch.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Neon Vision Editor started with a blank document and temporarily paused heavier startup features so you can recover safely.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if safeModeRecoveryPreparedForNextLaunch {
                Text("Normal startup will be used again on the next launch.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Button("Open File…") {
                    openFileFromToolbar()
                }
                .font(.subheadline.weight(.semibold))

                Button("Normal Next Launch") {
                    RuntimeReliabilityMonitor.shared.clearSafeModeRecoveryState()
                    safeModeRecoveryPreparedForNextLaunch = true
                }
                .font(.subheadline.weight(.semibold))

#if os(macOS)
                Button("Settings…") {
                    openSettings(tab: "general")
                }
                .font(.subheadline.weight(.semibold))
#endif
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safe Mode startup")
    }

    var startupRecentFilesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Files")
                .font(.headline)

            ForEach(startupRecentFiles) { item in
                HStack(spacing: 12) {
                    Button {
                        _ = viewModel.openFile(url: item.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button {
                        RecentFilesStore.togglePinned(item.url)
                    } label: {
                        Image(systemName: item.isPinned ? "star.fill" : "star")
                            .foregroundStyle(item.isPinned ? Color.yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isPinned ? "Unpin recent file" : "Pin recent file")
                    .accessibilityHint("Keeps this file near the top of recent files")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
            }

            Button("Open File…") {
                openFileFromToolbar()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent files")
    }

    var startupSharedImportsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shared Imports")
                .font(.headline)

            ForEach(sharedImportItems) { item in
                Button {
                    _ = viewModel.openFile(url: item.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
                .accessibilityLabel("Open shared import \(item.title)")
            }

            Button("Clear Import History") {
                SharedImportStore.clearHistory()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shared imports")
    }

    func openSharedImportURLs(_ urls: [URL]) {
        SharedImportStore.remember(urls)
        guard shareImportsAutoOpenEnabled else { return }
        for url in urls {
            _ = viewModel.openFile(url: url)
        }
    }

    func promptForSharedImportDestination(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        SharedImportStore.remember(urls)
        pendingSharedImportURLs = urls
        showSharedImportDestinationDialog = true
        sharedImportsRefreshToken = UUID()
    }

    func handleSharedImportURL(_ url: URL) {
        let importedURLs = ShareImportHandoff.importedFileURLs(from: url)
        let urls = importedURLs.isEmpty ? ShareImportHandoff.consumePendingImportedFileURLs() : importedURLs
        guard sharedImportAccessAllowed else {
            pendingSharedImportURL = urls.isEmpty ? url : nil
            pendingSharedImportURLs = urls
            if !urls.isEmpty || pendingSharedImportURL != nil {
                showSharedImportAccessExplanation = true
            }
            return
        }
        promptForSharedImportDestination(urls)
    }

    func consumePendingSharedImportsIfNeeded() {
        let urls = ShareImportHandoff.consumePendingImportedFileURLs()
        guard !urls.isEmpty else { return }
        guard sharedImportAccessAllowed else {
            pendingSharedImportURL = nil
            pendingSharedImportURLs = urls
            showSharedImportAccessExplanation = true
            return
        }
        promptForSharedImportDestination(urls)
    }

    func confirmSharedImportAccess() {
        sharedImportAccessAllowed = true
        if !pendingSharedImportURLs.isEmpty {
            let urls = pendingSharedImportURLs
            pendingSharedImportURLs = []
            promptForSharedImportDestination(urls)
            return
        }
        guard let url = pendingSharedImportURL else {
            sharedImportsRefreshToken = UUID()
            return
        }
        pendingSharedImportURL = nil
        promptForSharedImportDestination(ShareImportHandoff.importedFileURLs(from: url))
    }

    func cancelSharedImportAccess() {
        pendingSharedImportURL = nil
        pendingSharedImportURLs = []
        showSharedImportAccessExplanation = false
    }

    func openPendingSharedImportsInNewTabs() {
        let urls = pendingSharedImportURLs
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
        for url in urls {
            _ = viewModel.openFile(url: url)
        }
    }

    func replaceCurrentTabWithPendingSharedImport() {
        guard let url = pendingSharedImportURLs.first else {
            cancelPendingSharedImportDestination()
            return
        }
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
        _ = viewModel.replaceSelectedTabWithFile(url: url)
    }

    func cancelPendingSharedImportDestination() {
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
    }
}

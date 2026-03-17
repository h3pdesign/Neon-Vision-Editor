import SwiftUI

extension ContentView {
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
        return !startupRecentFiles.isEmpty
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
        shouldShowSafeModeStartupCard || shouldShowStartupRecentFilesCard
    }

    @ViewBuilder
    var startupOverlay: some View {
        VStack(alignment: .leading, spacing: 16) {
            if shouldShowSafeModeStartupCard {
                safeModeStartupCard
            }
            if shouldShowStartupRecentFilesCard {
                startupRecentFilesCard
            }
        }
        .padding(24)
    }

    var safeModeStartupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safe Mode", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.orange)

            Text(safeModeMessage ?? "Safe Mode is active for this launch.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Neon Vision Editor started with a blank document and skipped session restore plus startup diagnostics so you can recover safely.")
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
}

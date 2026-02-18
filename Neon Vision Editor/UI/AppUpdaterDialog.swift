import SwiftUI

struct AppUpdaterDialog: View {
    @EnvironmentObject private var appUpdateManager: AppUpdateManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("EnableTranslucentWindow") private var translucentWindow: Bool = false
    @AppStorage("SettingsLiquidGlassEnabled") private var liquidGlassEnabled: Bool = true
    @Binding var isPresented: Bool

    private var releaseTitle: String {
        appUpdateManager.latestRelease?.title ?? "Latest Release"
    }
    private var shouldUsePanelGlass: Bool {
        translucentWindow && liquidGlassEnabled && !reduceTransparency
    }
    var body: some View {
        GlassSurface(
            enabled: shouldUsePanelGlass,
            material: colorScheme == .dark ? .regularMaterial : .ultraThinMaterial,
            fallbackColor: Color.secondary.opacity(0.12),
            shape: .rounded(16)
        ) {
            VStack(spacing: 16) {
                header
                bodyContent
                actionRow
            }
            .padding(20)
            .frame(minWidth: 520, idealWidth: 560)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 38, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                    Color.white.opacity(0.9)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Software Update")
                    .font(.title3.weight(.semibold))
                Text("Checks GitHub releases for Neon Vision Editor updates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

#if os(macOS)
            Button("Show Installer Log") {
                appUpdateManager.openUpdaterLog()
            }
            .buttonStyle(.bordered)
#endif
        }
        .padding(14)
        .background(Color.clear)
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch appUpdateManager.status {
        case .idle, .checking:
            VStack(alignment: .leading, spacing: 12) {
                ProgressView()
                Text("Checking for updates…")
                    .font(.headline)
                Text("Current version: \(appUpdateManager.currentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

        case .upToDate:
            VStack(alignment: .leading, spacing: 10) {
                Label("You’re up to date.", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Current version: \(appUpdateManager.currentVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

        case .failed:
            VStack(alignment: .leading, spacing: 10) {
                Label("Update check failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(appUpdateManager.errorMessage ?? "Unknown error")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

        case .updateAvailable:
            VStack(alignment: .leading, spacing: 12) {
                Label("\(releaseTitle) is available", systemImage: "sparkles")
                    .font(.headline)
                Text("Current version: \(appUpdateManager.currentVersion)  •  New version: \(appUpdateManager.latestRelease?.version ?? "-")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let date = appUpdateManager.latestRelease?.publishedAt {
                    Text("Published: \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let notes = appUpdateManager.latestRelease?.notes,
                   !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ScrollView {
                        Text(notes)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                }

                Text("Updates are delivered from GitHub release assets, not App Store updates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if appUpdateManager.isInstalling {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: appUpdateManager.installProgress, total: 1.0) {
                            Text(appUpdateManager.installPhase.isEmpty ? "Installing update…" : appUpdateManager.installPhase)
                                .font(.caption)
                        }
                        Text("\(Int((appUpdateManager.installProgress * 100).rounded()))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let installMessage = appUpdateManager.installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let reason = appUpdateManager.installNowDisabledReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        HStack {
            switch appUpdateManager.status {
            case .updateAvailable:
                if appUpdateManager.awaitingInstallCompletionAction {
                    Button("Later") {
                        isPresented = false
                    }

                    Spacer()

#if os(macOS)
                    Button("Install and Close App") {
                        appUpdateManager.installAndCloseApp()
                    }

                    Button("Restart and Install") {
                        appUpdateManager.restartAndInstall()
                    }
                    .buttonStyle(.borderedProminent)
#else
                    Button("View Releases") {
                        appUpdateManager.openReleasePage()
                    }
#endif
                } else {
                    Button("Skip This Version") {
                        appUpdateManager.skipCurrentVersion()
                        isPresented = false
                    }

                    Button("Remind Me Tomorrow") {
                        appUpdateManager.remindMeTomorrow()
                        isPresented = false
                    }

                    Spacer()

                    Button("View Releases") {
                        appUpdateManager.openReleasePage()
                    }

#if os(macOS)
                    Button("Install Update") {
                        Task {
                            await appUpdateManager.installUpdateNow()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appUpdateManager.isInstalling || !appUpdateManager.installNowSupported)
#endif
                }
            case .failed:
                Button("Close") {
                    isPresented = false
                }

                Spacer()

                Button("Try Again") {
                    Task {
                        await appUpdateManager.checkForUpdates(source: .manual)
                    }
                }
                .buttonStyle(.borderedProminent)

            case .upToDate:
                Button("Close") {
                    isPresented = false
                }

                Spacer()

                Button("View Releases") {
                    appUpdateManager.openReleasePage()
                }

                Button("Check Again") {
                    Task {
                        await appUpdateManager.checkForUpdates(source: .manual)
                    }
                }
                .buttonStyle(.borderedProminent)

            case .idle, .checking:
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .disabled(appUpdateManager.status == .checking)
            }
        }
    }
}

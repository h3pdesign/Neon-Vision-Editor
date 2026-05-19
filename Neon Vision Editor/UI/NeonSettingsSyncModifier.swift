import SwiftUI

struct AppearanceThemeSettingsSyncModifier: ViewModifier {
    @Binding var syncEnabled: Bool
    @Binding var syncStatus: String
    @Binding var selectedTheme: String
    let syncFingerprint: String
    let canonicalThemeName: (String) -> String
    let applyAppearance: () -> Void
    @State private var pendingPushTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onAppear {
                applyResult(AppearanceThemeCloudSync.syncIfEnabled())
            }
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification)) { _ in
                applyResult(AppearanceThemeCloudSync.syncIfEnabled())
            }
            .onChange(of: syncEnabled) { _, enabled in
                applyResult(AppearanceThemeCloudSync.setEnabled(enabled))
            }
            .onChange(of: syncFingerprint) { _, _ in
                scheduleLocalChangePush()
            }
    }

    private func scheduleLocalChangePush() {
        pendingPushTask?.cancel()
        pendingPushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            applyResult(AppearanceThemeCloudSync.recordLocalChangeAndPush())
            pendingPushTask = nil
        }
    }

    private func applyResult(_ result: AppearanceThemeCloudSyncResult?) {
        guard let result else { return }
        syncStatus = result.message
        guard result.didApplyRemoteSettings else { return }
        selectedTheme = canonicalThemeName(selectedTheme)
        applyAppearance()
    }
}

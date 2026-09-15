import SwiftUI

struct ConfiguredSettingsView: View {
    let supportsOpenInTabs: Bool
    let supportsTranslucency: Bool
    let editorViewModel: EditorViewModel

    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @ObservedObject var appUpdateManager: AppUpdateManager

    var body: some View {
        NeonSettingsView(
            supportsOpenInTabs: supportsOpenInTabs,
            supportsTranslucency: supportsTranslucency
        )
        .environment(editorViewModel)
        .environmentObject(supportPurchaseManager)
        .environmentObject(appUpdateManager)
    }
}

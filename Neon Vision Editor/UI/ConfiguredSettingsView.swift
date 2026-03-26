import SwiftUI

struct ConfiguredSettingsView: View {
    let supportsOpenInTabs: Bool
    let supportsTranslucency: Bool

    @ObservedObject var supportPurchaseManager: SupportPurchaseManager
    @ObservedObject var appUpdateManager: AppUpdateManager

    var body: some View {
        NeonSettingsView(
            supportsOpenInTabs: supportsOpenInTabs,
            supportsTranslucency: supportsTranslucency
        )
        .environmentObject(supportPurchaseManager)
        .environmentObject(appUpdateManager)
    }
}

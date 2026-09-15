import SwiftUI

@main
struct NeonPulseWatchApp: App {
    @State private var model = NeonPulseWatchModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NeonPulseRootView(model: model)
            }
            .tint(.cyan)
        }
    }
}

import SwiftUI

@main
struct NeonVisionEditorAppClip: App {
    var body: some Scene {
        WindowGroup {
            AppClipRootView()
        }
    }
}

private struct AppClipRootView: View {
    @State private var scratchText = ""
    @State private var invocationHost: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $scratchText)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityLabel("Scratch editor")

                if let invocationHost {
                    Text(invocationHost)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
            .navigationTitle("Neon Vision Clip")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        scratchText = ""
                    }
                    .disabled(scratchText.isEmpty)
                }
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            invocationHost = activity.webpageURL?.host()
        }
    }
}

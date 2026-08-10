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
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    TextEditor(text: $scratchText)
                        .focused($isEditorFocused)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .scrollContentBackground(.hidden)
                        .background(Color(uiColor: .systemBackground))
                        .accessibilityLabel("Scratch editor")

                    if scratchText.isEmpty {
                        AppClipWelcomeCard {
                            isEditorFocused = true
                        }
                    }
                }

                if let invocationHost {
                    Label("Opened from \(invocationHost)", systemImage: "link")
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

private struct AppClipWelcomeCard: View {
    let startWriting: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.tint)

            Text("Quick text editor")
                .font(.headline)

            Text("Type or paste text to start a temporary note.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Start writing", systemImage: "pencil") {
                startWriting()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Places the cursor in the scratch editor")
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(24)
        .accessibilityElement(children: .contain)
    }
}

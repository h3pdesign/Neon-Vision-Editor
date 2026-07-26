import SwiftUI

struct NeonPulseRootView: View {
    let model: NeonPulseWatchModel
    @State private var draft = ""
    @State private var selectedPage = 0
    var body: some View {
        TabView(selection: $selectedPage) {
            statusPage.tag(0)
            capturePage.tag(1)
            inboxPage.tag(2)
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(.blue.gradient.opacity(0.35), for: .tabView)
    }

    private var statusPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Neon Pulse", systemImage: "waveform.path.ecg")
                    .font(.headline)
                statusRow("Document", value: model.status.currentDocument ?? "No recent document")
                statusRow("Pending", value: "\(model.status.pendingChanges) changes")
                if let lastSave = model.status.lastSuccessfulSave {
                    statusRow("Last save", value: lastSave.formatted(date: .omitted, time: .shortened))
                }
                if model.status.hasConflict {
                    Label("Sync conflict", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("A sync conflict needs attention")
                }
                Text(model.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .privacySensitive()
        .accessibilityElement(children: .contain)
    }

    private var capturePage: some View {
        VStack(spacing: 10) {
            Label("Capture", systemImage: "mic.fill")
                .font(.headline)
            TextField("Note, TODO, or bug", text: $draft, axis: .vertical)
                .privacySensitive()
                .accessibilityHint("Use dictation or Scribble to add text to Neon Inbox")
            if #available(watchOS 11.0, *) {
                captureButton
                    .handGestureShortcut(.primaryAction)
            } else {
                captureButton
            }
        }
    }

    private var captureButton: some View {
        Button {
            if model.capture(draft) { draft = "" }
        } label: {
            Label("Save to Inbox", systemImage: "tray.and.arrow.down.fill")
        }
        .buttonStyle(.borderedProminent)
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var inboxPage: some View {
        List {
            if model.captures.isEmpty {
                ContentUnavailableView("Inbox Empty", systemImage: "tray", description: Text("Captured ideas appear here."))
            } else {
                ForEach(model.captures.prefix(10)) { capture in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(capture.text)
                        Label(
                            capture.deliveredAt == nil ? "Pending" : "Delivered",
                            systemImage: capture.deliveredAt == nil ? "clock" : "checkmark.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(capture.deliveredAt == nil ? .orange : .green)
                        .accessibilityLabel(capture.deliveredAt == nil ? "Pending delivery" : "Delivered to iPhone")
                    }
                    .privacySensitive()
                }
            }
        }
        .navigationTitle("Inbox")
        .toolbar {
            if model.pendingCaptureCount > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.retryPendingCaptures() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Retry pending captures")
                }
            }
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body).privacySensitive()
        }
    }
}

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
        .containerBackground(.black.opacity(0.92), for: .tabView)
    }

    private var statusPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Label("Neon Pulse", systemImage: "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                statusSummary
                HStack(spacing: 8) {
                    metricTile("Pending", value: "\(model.pendingCaptureCount)", systemImage: "tray.fill", tint: .orange)
                    metricTile("Changes", value: "\(model.status.pendingChanges)", systemImage: "arrow.triangle.2.circlepath", tint: .cyan)
                }
                statusDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .privacySensitive()
        .accessibilityElement(children: .contain)
    }

    private var statusSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                model.status.hasConflict ? "Needs attention" : (model.pendingCaptureCount == 0 ? "Ready" : "Waiting to deliver"),
                systemImage: model.status.hasConflict ? "exclamationmark.triangle.fill" : (model.pendingCaptureCount == 0 ? "checkmark.circle.fill" : "clock.fill")
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(model.status.hasConflict ? .orange : (model.pendingCaptureCount == 0 ? .green : .yellow))
            Text(model.status.hasConflict ? "Review sync on iPhone" : NeonPulseConstants.inboxFilename)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.status.hasConflict ? "Needs attention. Review sync on iPhone" : "Delivery target: \(NeonPulseConstants.inboxFilename). \(model.pendingCaptureCount == 0 ? "Ready" : "Waiting to deliver")")
    }

    private var statusDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let lastSave = model.status.lastSuccessfulSave {
                statusRow("Last save", value: lastSave.formatted(date: .omitted, time: .shortened))
            }
            Label(model.connectionLabel, systemImage: model.connectionLabel == NSLocalizedString("Delivered", comment: "Watch connectivity status") ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                .font(.caption2)
                .foregroundStyle(model.connectionLabel == NSLocalizedString("Delivered", comment: "Watch connectivity status") ? .green : .secondary)
                .accessibilityLabel("Watch connection: \(model.connectionLabel)")
            if model.pendingCaptureCount > 0 {
                Button {
                    model.retryPendingCaptures()
                } label: {
                    Label("Try delivery again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Attempts to send pending captures to iPhone")
            }
        }
    }

    private func metricTile(_ title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var capturePage: some View {
        VStack(spacing: 10) {
            Label("Capture", systemImage: "mic.fill")
                .font(.headline)
                .foregroundStyle(.cyan)
            TextField("Note, TODO, or bug", text: $draft, axis: .vertical)
                .privacySensitive()
                .lineLimit(2...4)
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
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text("Inbox Empty")
                        .font(.headline)
                    Text("Captured ideas appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
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

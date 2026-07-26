import SwiftUI
import WidgetKit

struct NeonPulseEntry: TimelineEntry {
    let date: Date
    let status: NeonPulseStatus
    let pendingCaptures: Int
}

struct NeonPulseProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeonPulseEntry {
        NeonPulseEntry(date: .now, status: .empty, pendingCaptures: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NeonPulseEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NeonPulseEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry() -> NeonPulseEntry {
        let store = NeonPulseStore()
        return NeonPulseEntry(
            date: .now,
            status: store.status(),
            pendingCaptures: store.captures().filter { $0.deliveredAt == nil }.count
        )
    }
}

struct NeonPulseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NeonPulseEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.pendingCaptures), in: 0...max(1, Double(entry.pendingCaptures))) {
                Image(systemName: "tray.fill")
            } currentValueLabel: {
                Text("\(entry.pendingCaptures)")
            }
            .accessibilityLabel("\(entry.pendingCaptures) pending Neon captures")
        case .accessoryInline:
            Label("\(entry.pendingCaptures) pending", systemImage: "waveform.path.ecg")
                .accessibilityLabel("Neon Pulse, \(entry.pendingCaptures) pending captures")
        default:
            VStack(alignment: .leading, spacing: 3) {
                Label("Neon Pulse", systemImage: entry.status.hasConflict ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                    .font(.headline)
                Text(entry.status.currentDocument ?? "Ready to capture")
                    .font(.caption)
                    .privacySensitive()
                Text("\(entry.pendingCaptures) pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Neon Pulse. \(entry.pendingCaptures) pending captures")
        }
    }
}

@main
struct NeonPulseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NeonPulseStatus", provider: NeonPulseProvider()) { entry in
            NeonPulseWidgetView(entry: entry)
                .containerBackground(.blue.gradient, for: .widget)
        }
        .configurationDisplayName("Neon Pulse")
        .description("See pending captures and the latest editor status.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

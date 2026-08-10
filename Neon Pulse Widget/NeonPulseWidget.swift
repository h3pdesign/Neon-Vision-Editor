import SwiftUI
import WidgetKit

struct NeonPulseEntry: TimelineEntry {
    let date: Date
    let status: NeonPulseStatus
    let pendingCaptures: Int
}

struct NeonPulseInboxEntry: TimelineEntry {
    let date: Date
    let pendingCaptures: Int
    let latestCapture: NeonPulseCapture?
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

struct NeonPulseInboxProvider: TimelineProvider {
    func placeholder(in context: Context) -> NeonPulseInboxEntry {
        NeonPulseInboxEntry(
            date: .now,
            pendingCaptures: 1,
            latestCapture: NeonPulseCapture(text: "Capture a thought")
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NeonPulseInboxEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NeonPulseInboxEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func entry() -> NeonPulseInboxEntry {
        let captures = NeonPulseStore().captures()
        return NeonPulseInboxEntry(
            date: .now,
            pendingCaptures: captures.lazy.filter { $0.deliveredAt == nil }.count,
            latestCapture: captures.first
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
                Image(systemName: entry.status.hasConflict ? "exclamationmark.triangle.fill" : "tray.fill")
            } currentValueLabel: {
                Text("\(entry.pendingCaptures)")
            }
            .tint(entry.status.hasConflict ? .orange : .cyan)
            .accessibilityLabel(circularAccessibilityLabel)
        case .accessoryCorner:
            Text("\(entry.pendingCaptures)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(entry.status.hasConflict ? .orange : .cyan)
                .widgetLabel {
                    Label("Pending captures", systemImage: entry.status.hasConflict ? "exclamationmark.triangle.fill" : "tray.fill")
                }
                .accessibilityLabel(circularAccessibilityLabel)
        case .accessoryInline:
            Label(inlineLabel, systemImage: entry.status.hasConflict ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                .foregroundStyle(entry.status.hasConflict ? .orange : .primary)
                .accessibilityLabel("Neon Pulse. \(inlineLabel)")
                .lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 3) {
                Label(entry.status.hasConflict ? "Needs attention" : "Neon Pulse", systemImage: entry.status.hasConflict ? "exclamationmark.triangle.fill" : "waveform.path.ecg")
                    .font(.headline)
                    .foregroundStyle(entry.status.hasConflict ? .orange : .cyan)
                Text(entry.status.currentDocument ?? "Ready to capture")
                    .font(.caption)
                    .privacySensitive()
                    .lineLimit(1)
                Text("\(entry.pendingCaptures) pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if entry.status.updatedAt != .distantPast {
                    Text("Updated \(entry.status.updatedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(rectangularAccessibilityLabel)
        }
    }

    private var inlineLabel: String {
        if entry.status.hasConflict { return "Sync needs attention" }
        return entry.pendingCaptures == 0 ? "Ready" : "\(entry.pendingCaptures) pending"
    }

    private var circularAccessibilityLabel: String {
        if entry.status.hasConflict {
            return "Neon Pulse. Sync needs attention. \(entry.pendingCaptures) pending captures"
        }
        return "Neon Pulse. \(entry.pendingCaptures) pending captures"
    }

    private var rectangularAccessibilityLabel: String {
        if entry.status.hasConflict {
            return "Neon Pulse. Sync needs attention. \(entry.pendingCaptures) pending captures"
        }
        let document = entry.status.currentDocument ?? "Ready to capture"
        return "Neon Pulse. \(document). \(entry.pendingCaptures) pending captures"
    }
}

struct NeonPulseInboxWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NeonPulseInboxEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: Double(entry.pendingCaptures), in: 0...max(1, Double(entry.pendingCaptures))) {
                Image(systemName: "tray.fill")
            } currentValueLabel: {
                Text("\(entry.pendingCaptures)")
            }
            .tint(.orange)
            .accessibilityLabel(accessibilityLabel)
        case .accessoryCorner:
            Text("\(entry.pendingCaptures)")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.orange)
                .widgetLabel {
                    Label("Inbox pending", systemImage: "tray.fill")
                }
                .accessibilityLabel(accessibilityLabel)
        case .accessoryInline:
            Label(inlineLabel, systemImage: "tray.fill")
                .accessibilityLabel("Neon Inbox. \(inlineLabel)")
                .lineLimit(1)
        default:
            VStack(alignment: .leading, spacing: 3) {
                Label("Neon Inbox", systemImage: "tray.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                if let latestCapture = entry.latestCapture {
                    Text(latestCapture.text)
                        .font(.caption)
                        .lineLimit(2)
                        .privacySensitive()
                } else {
                    Text("No captures yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(entry.pendingCaptures) pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private var inlineLabel: String {
        entry.pendingCaptures == 0 ? "Inbox ready" : "\(entry.pendingCaptures) pending"
    }

    private var accessibilityLabel: String {
        if let latestCapture = entry.latestCapture {
            return "Neon Inbox. \(entry.pendingCaptures) pending captures. Latest: \(latestCapture.text)"
        }
        return "Neon Inbox. No captures yet"
    }
}

@main
struct NeonPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        NeonPulseStatusWidget()
        NeonPulseInboxWidget()
    }
}

struct NeonPulseStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NeonPulseStatus", provider: NeonPulseProvider()) { entry in
            NeonPulseWidgetView(entry: entry)
                .containerBackground(.blue.gradient, for: .widget)
        }
        .configurationDisplayName("Neon Pulse Status")
        .description("See capture delivery and editor sync status at a glance.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NeonPulseInboxWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NeonPulseInbox", provider: NeonPulseInboxProvider()) { entry in
            NeonPulseInboxWidgetView(entry: entry)
                .containerBackground(.orange.gradient, for: .widget)
        }
        .configurationDisplayName("Neon Inbox")
        .description("See pending captures and the latest inbox note.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

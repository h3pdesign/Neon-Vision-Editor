import SwiftUI



/// MARK: - Types

struct AIActivityLogView: View {
    @State private var log = AIActivityLog.shared

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if log.entries.isEmpty {
                emptyState
            } else {
                List(log.entries.reversed()) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Self.timestampFormatter.string(from: entry.timestamp))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Time \(Self.timestampFormatter.string(from: entry.timestamp))")
                        Text(entry.level.rawValue)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(levelColor(entry.level))
                        Text("[\(entry.source)]")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(entry.message)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("AI Activity Log")
    }

    private var header: some View {
        HStack {
            Text("AI Activity Log")
                .font(.headline)
            Spacer()
            Button("Clear") {
                log.clear()
            }
            .disabled(log.entries.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No AI activity yet")
                .font(.headline)
            Text("Actions like AI checks and suggestions will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func levelColor(_ level: AIActivityLog.Level) -> Color {
        switch level {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

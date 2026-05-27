import SwiftUI

struct NeonSettingsDropdownPickerModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let maxWidth: CGFloat?

    func body(content: Content) -> some View {
        content
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .tint(Color.primary)
            .padding(.leading, 14)
            .padding(.trailing, trailingPadding)
            .padding(.vertical, verticalPadding)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(background)
            .overlay(alignment: .trailing) {
#if os(macOS)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.secondary)
                    .accessibilityHidden(true)
                    .padding(.trailing, 11)
#endif
            }
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07), radius: 8, x: 0, y: 3)
            .opacity(isEnabled ? 1 : 0.56)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(dropdownFill)
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.10 : 0.38), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.43, blue: 0.94).opacity(isEnabled ? 0.42 : 0.14),
                        Color.secondary.opacity(isEnabled ? 0.18 : 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    private var dropdownFill: Color {
#if os(macOS)
        colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.96)
            : Color(nsColor: .textBackgroundColor).opacity(0.98)
#else
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemGroupedBackground).opacity(0.96)
            : Color(uiColor: .systemBackground).opacity(0.98)
#endif
    }

    private var cornerRadius: CGFloat {
        horizontalSizeClass == .compact ? 14 : 16
    }

    private var minHeight: CGFloat {
        horizontalSizeClass == .compact ? 34 : 36
    }

    private var verticalPadding: CGFloat {
        horizontalSizeClass == .compact ? 4 : 5
    }

    private var trailingPadding: CGFloat {
#if os(macOS)
        28
#else
        14
#endif
    }
}

extension View {
    func neonSettingsDropdown(maxWidth: CGFloat? = 240) -> some View {
        modifier(NeonSettingsDropdownPickerModifier(maxWidth: maxWidth))
    }
}

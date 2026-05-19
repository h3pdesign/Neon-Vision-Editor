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
            .font(.headline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.vertical, verticalPadding)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.56)
            .frame(maxWidth: maxWidth, alignment: .leading)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.43, blue: 0.94).opacity(colorScheme == .dark ? 0.24 : 0.12),
                        Color(red: 0.06, green: 0.65, blue: 0.72).opacity(colorScheme == .dark ? 0.18 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color(red: 0.10, green: 0.43, blue: 0.94).opacity(isEnabled ? 0.32 : 0.14), lineWidth: 1)
    }

    private var cornerRadius: CGFloat {
        horizontalSizeClass == .compact ? 14 : 16
    }

    private var minHeight: CGFloat {
        horizontalSizeClass == .compact ? 44 : 48
    }

    private var verticalPadding: CGFloat {
        horizontalSizeClass == .compact ? 8 : 10
    }
}

extension View {
    func neonSettingsDropdown(maxWidth: CGFloat? = 240) -> some View {
        modifier(NeonSettingsDropdownPickerModifier(maxWidth: maxWidth))
    }
}

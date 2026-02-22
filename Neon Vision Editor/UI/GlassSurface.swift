import SwiftUI

enum GlassShapeKind {
    case capsule
    case circle
    case rounded(CGFloat)
}

enum GlassChromeStyle {
    case dual
    case single
    case none
}

struct GlassSurface<Content: View>: View {
    let enabled: Bool
    let material: Material
    let fallbackColor: Color
    let shape: GlassShapeKind
    let chromeStyle: GlassChromeStyle
    let content: Content

    init(
        enabled: Bool,
        material: Material = .thinMaterial,
        fallbackColor: Color = Color.secondary.opacity(0.12),
        shape: GlassShapeKind = .rounded(14),
        chromeStyle: GlassChromeStyle = .dual,
        @ViewBuilder content: () -> Content
    ) {
        self.enabled = enabled
        self.material = material
        self.fallbackColor = fallbackColor
        self.shape = shape
        self.chromeStyle = chromeStyle
        self.content = content()
    }

    var body: some View {
        content
            .background(backgroundStyle)
            .overlay(primaryChromeShape)
            .overlay(secondaryChromeShape)
    }

    @ViewBuilder
    private var backgroundStyle: some View {
        switch shape {
        case .capsule:
            Capsule(style: .continuous)
                .fill(enabled ? AnyShapeStyle(material) : AnyShapeStyle(fallbackColor))
        case .circle:
            Circle()
                .fill(enabled ? AnyShapeStyle(material) : AnyShapeStyle(fallbackColor))
        case .rounded(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(enabled ? AnyShapeStyle(material) : AnyShapeStyle(fallbackColor))
        }
    }

    @ViewBuilder
    private var primaryChromeShape: some View {
        if chromeStyle == .none {
            EmptyView()
        } else {
            let opacity = enabled ? 0.18 : 0.1
            switch shape {
            case .capsule:
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(opacity), lineWidth: 0.8)
            case .circle:
                Circle()
                    .stroke(Color.white.opacity(opacity), lineWidth: 0.8)
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(opacity), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder
    private var secondaryChromeShape: some View {
        if chromeStyle != .dual {
            EmptyView()
        } else {
            let glowOpacity = enabled ? 0.10 : 0.04
            switch shape {
            case .capsule:
                Capsule(style: .continuous)
                    .inset(by: 1)
                    .stroke(Color.white.opacity(glowOpacity), lineWidth: 0.6)
            case .circle:
                Circle()
                    .inset(by: 1)
                    .stroke(Color.white.opacity(glowOpacity), lineWidth: 0.6)
            case .rounded(let radius):
                RoundedRectangle(cornerRadius: max(0, radius - 1), style: .continuous)
                    .inset(by: 1)
                    .stroke(Color.white.opacity(glowOpacity), lineWidth: 0.6)
            }
        }
    }
}

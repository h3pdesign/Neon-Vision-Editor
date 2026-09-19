import SwiftUI
#if os(iOS)
import UIKit

enum IOSClearGlassAppearance {
    static func apply(to view: UIVisualEffectView) {
        view.isOpaque = false
        if #available(iOS 26.0, *) {
            // Let the system adjust its glass for Clear/Tinted and accessibility settings.
            view.backgroundColor = .clear
            view.effect = UIGlassEffect(style: .clear)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            view.effect = nil
            view.backgroundColor = .secondarySystemBackground
        } else {
            view.backgroundColor = .clear
            view.effect = UIBlurEffect(style: .systemChromeMaterial)
        }
    }
}

struct IOSClearGlassBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        IOSClearGlassAppearance.apply(to: view)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        IOSClearGlassAppearance.apply(to: view)
    }
}

enum IOSReadableGlassAppearance {
    static func apply(to view: UIVisualEffectView) {
        view.isOpaque = false
        if #available(iOS 26.0, *) {
            view.backgroundColor = .clear
            // Regular glass follows the user's system Clear/Tinted Liquid Glass
            // choice and accessibility contrast settings. Do not override tintColor.
            view.effect = UIGlassEffect(style: .regular)
        } else if UIAccessibility.isReduceTransparencyEnabled {
            view.effect = nil
            view.backgroundColor = .secondarySystemBackground
        } else {
            view.backgroundColor = .clear
            view.effect = UIBlurEffect(style: .systemChromeMaterial)
        }
    }
}

struct IOSReadableGlassBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView()
        IOSReadableGlassAppearance.apply(to: view)
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        IOSReadableGlassAppearance.apply(to: view)
    }
}
#endif



// MARK: - Types

enum GlassShapeKind {
    case capsule
    case circle
    case rounded(CGFloat)
}

#if os(macOS)
struct MacToolbarVisibilityModifier: ViewModifier {
    var hidden: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content
                .toolbar(hidden ? .hidden : .automatic, for: .windowToolbar)
                .toolbarBackgroundVisibility(hidden ? .hidden : .visible, for: .windowToolbar)
        } else {
            content
        }
    }
}
#endif

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
        glassContent
    }

    @ViewBuilder
    private var glassContent: some View {
#if os(visionOS)
        if enabled {
            content
                .glassBackgroundEffect(displayMode: .always)
                .overlay(primaryChromeShape)
                .overlay(secondaryChromeShape)
        } else {
            content
                .background(backgroundStyle)
                .overlay(primaryChromeShape)
                .overlay(secondaryChromeShape)
        }
#else
#if os(macOS) || os(iOS)
        if enabled, #available(macOS 26.0, iOS 26.0, *) {
            nativeGlassContent
        } else {
            legacyGlassContent
        }
#else
        legacyGlassContent
#endif
#endif
    }

    private var legacyGlassContent: some View {
        content
            .background(backgroundStyle)
            .overlay(primaryChromeShape)
            .overlay(secondaryChromeShape)
    }

#if os(macOS) || os(iOS)
    @available(macOS 26.0, iOS 26.0, *)
    @ViewBuilder
    private var nativeGlassContent: some View {
        switch shape {
        case .capsule:
            content.glassEffect(.regular, in: Capsule())
        case .circle:
            content.glassEffect(.regular, in: Circle())
        case .rounded(let radius):
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }
#endif

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

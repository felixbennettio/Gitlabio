import SwiftUI

// Liquid Glass on iOS 26+, with a material-based fallback on iOS 18–25.
// System bars, tab bars and sheets adopt glass automatically when built with the iOS 26 SDK;
// these helpers cover the custom floating surfaces.

extension View {
    /// A content card: a material surface with a hairline border. Liquid Glass is reserved for
    /// controls (chips, buttons, floating bars), following Apple's guidance for content layers.
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil, interactive: Bool = false) -> some View {
        background { CardSurface(cornerRadius: cornerRadius, tint: tint) }
    }

    /// Glass capsule for chips, pills and compact floating controls.
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: .capsule)
        } else {
            self.background {
                Capsule().fill(.thinMaterial)
                    .overlay { if let tint { Capsule().fill(tint.opacity(0.14)) } }
                    .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5) }
            }
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// Prominent glass button on iOS 26, bordered-prominent before.
    @ViewBuilder
    func glassProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Plain (non-glass) solid card used for dense content such as code and diffs.
    func solidCard(cornerRadius: CGFloat = 18) -> some View {
        background(.background.secondary, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct CardSurface: View {
    let cornerRadius: CGFloat
    var tint: Color?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(.regularMaterial)
            .overlay { if let tint { shape.fill(tint.opacity(scheme == .dark ? 0.14 : 0.08)) } }
            .overlay { shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.5) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 10, y: 3)
    }
}

/// Solid brand-gradient button for the primary action on a screen.
struct BrandButtonStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        BrandButton(configuration: configuration, tint: tint)
    }

    private struct BrandButton: View {
        let configuration: ButtonStyleConfiguration
        let tint: Color?
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.vertical, 13)
                .padding(.horizontal, 18)
                // The colour's own gradient: the CI simulator rendered a custom two-colour
                // LinearGradient here as a muddy tan, while `Color.gradient` stays vivid.
                .background { Capsule().fill((tint ?? Theme.orange).gradient) }
                .shadow(color: (tint ?? Theme.orange).opacity(0.35), radius: 10, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
        }
    }
}

/// Secondary action: Liquid Glass capsule on iOS 26, material capsule before.
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .glassCapsule(interactive: true)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Groups glass shapes so nearby ones blend and morph (iOS 26); a plain stack before.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Soft brand-tinted backdrop that gives glass surfaces something to refract.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var accent: Color = Theme.orange

    var body: some View {
        let dark = scheme == .dark
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.6, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1]
        ], colors: [
            accent.opacity(dark ? 0.30 : 0.22), Theme.purple.opacity(dark ? 0.22 : 0.12), Theme.purple.opacity(dark ? 0.30 : 0.18),
            Theme.coral.opacity(dark ? 0.10 : 0.06), .clear, Theme.indigo.opacity(dark ? 0.12 : 0.06),
            .clear, .clear, accent.opacity(dark ? 0.08 : 0.05)
        ])
        .background(Color(white: dark ? 0.04 : 0.97))
        .ignoresSafeArea()
    }
}

extension View {
    func ambientBackground(_ accent: Color = Theme.orange) -> some View {
        background { AmbientBackground(accent: accent) }
    }
}

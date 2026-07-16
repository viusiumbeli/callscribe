import SwiftUI

/// Brand colors, matching the app icon (indigo→violet). `brand` is the app-wide
/// accent/tint; `brandGradient` is available for hero flourishes. Keep these in
/// sync with `scripts/make-icon.swift`.
extension Color {
    /// Indigo #4F46E5 — primary accent.
    static let brand = Color(red: 0.31, green: 0.27, blue: 0.90)
    /// Violet #7C3AED — secondary.
    static let brandViolet = Color(red: 0.49, green: 0.23, blue: 0.93)
}

extension LinearGradient {
    /// Indigo→violet, matching the icon's squircle.
    static let brand = LinearGradient(
        colors: [.brand, .brandViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Consistent spacing scale (replaces ad-hoc values) — a small 4-based system.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}

// MARK: - Elevated card surface

/// A floating card: translucent material, continuous 16pt corners, a hairline
/// top border for definition, and a soft shadow — replaces the old flat
/// gray-box-with-1px-border look.
private struct CardSurface: ViewModifier {
    var padding: CGFloat = Spacing.lg
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
    }
}

extension View {
    /// Wrap content in the standard elevated card surface.
    func card(padding: CGFloat = Spacing.lg) -> some View {
        modifier(CardSurface(padding: padding))
    }
}

// MARK: - Button styles

/// The primary/hero action: filled with the brand gradient, white bold label,
/// gentle press feedback. Use sparingly (Record, main call-to-action).
struct BrandButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(LinearGradient.brand)
    var glow: Color = .brand
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: glow.opacity(configuration.isPressed ? 0.1 : 0.35), radius: 8, y: 3)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A clean secondary button: soft filled capsule, adapts to light/dark.
struct SoftButtonStyle: ButtonStyle {
    var tint: Color = .primary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .padding(.vertical, 7)
            .padding(.horizontal, 14)
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08),
                        in: Capsule(style: .continuous))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .contentShape(Capsule())
    }
}

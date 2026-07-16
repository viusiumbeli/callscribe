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

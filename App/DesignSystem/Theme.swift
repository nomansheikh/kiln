import AppKit
import SwiftUI

/// Shared look, modelled on Jan: a flat, airy main area, a floating sidebar
/// with a soft blue wash, white cards with hairline borders, one sky-blue accent.
enum Theme {
    static let accent = Color(red: 0.24, green: 0.70, blue: 0.88)
    /// Kept as a gradient type so call sites can use it as a fill; it is a flat colour.
    static let accentGradient = LinearGradient(colors: [accent, accent], startPoint: .top, endPoint: .bottom)

    static let panelRadius: CGFloat = 16
    static let cardRadius: CGFloat = 14
    static let contentWidth: CGFloat = 820

    /// The main area's background.
    static let window = Color(light: .white, dark: NSColor(white: 0.115, alpha: 1))
    static let panel = window
    /// Raised white surfaces: cards, the composer, pills.
    static let surface = Color(light: .white, dark: NSColor(white: 0.165, alpha: 1))
    /// Quiet grey fill for fields and round buttons.
    static let card = Color.primary.opacity(0.05)
    static let cardHover = Color.primary.opacity(0.085)
    static let hairline = Color.primary.opacity(0.09)

    /// The sidebar's wash, strongest at the top.
    static let sidebarGradient = LinearGradient(
        colors: [
            Color(light: NSColor(red: 0.77, green: 0.90, blue: 0.95, alpha: 1), dark: NSColor(red: 0.10, green: 0.21, blue: 0.27, alpha: 1)),
            Color(light: NSColor(red: 0.93, green: 0.97, blue: 0.99, alpha: 1), dark: NSColor(red: 0.12, green: 0.15, blue: 0.17, alpha: 1)),
            Color(light: NSColor(white: 0.995, alpha: 1), dark: NSColor(white: 0.13, alpha: 1)),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Centred screen headlines.
    static let roundedTitle = Font.system(size: 23, weight: .medium, design: .rounded)
}

extension Color {
    /// A colour that follows the window's light or dark appearance.
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

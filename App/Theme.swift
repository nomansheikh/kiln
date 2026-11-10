import AppKit
import ImageIO
import KilnCore
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

extension View {
    /// A white rounded card with a hairline border and a very soft shadow.
    func card(padding: CGFloat = 16, radius: CGFloat = Theme.cardRadius) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.hairline))
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

/// Large in-panel title row used at the top of every screen instead of a window toolbar.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Small rounded label for metadata such as size or quantization.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.14), in: Capsule())
    }
}

/// Square tile with an initial on a colour derived from the name, like an author avatar.
struct AvatarTile: View {
    let name: String
    var size: CGFloat = 40

    private var hue: Double {
        Double(name.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value } % 360) / 360
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.55, brightness: 0.85), Color(hue: hue, saturation: 0.7, brightness: 0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.first { $0.isLetter || $0.isNumber } ?? "?").uppercased())
                    .font(.system(size: size * 0.45, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

/// Coloured dot with a label saying whether a model fits this Mac's memory.
struct FitLabel: View {
    let fit: MemoryFit
    let memoryGB: Int
    var compact = false

    private var color: Color {
        switch fit {
        case .comfortable: .green
        case .tight: .yellow
        case .tooLarge: .red
        }
    }

    private var text: String {
        switch fit {
        case .comfortable: "Fits your \(memoryGB) GB Mac"
        case .tight: "Tight fit on \(memoryGB) GB"
        case .tooLarge: "Needs more than \(memoryGB) GB"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            if !compact {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(text)
    }
}

/// Filled accent button, the app's primary action style.
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// Quiet rounded button for secondary actions.
struct SoftButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(configuration.isPressed ? Theme.cardHover : Theme.card, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}

/// A downsampled image loaded off the main thread, for grids and lists.
struct Thumbnail: View {
    let url: URL
    var maxPixelSize = 400

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Theme.card
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            }
        }
        .task(id: url) {
            image = await Self.load(url, maxPixelSize: maxPixelSize)
        }
    }

    private struct Loaded: @unchecked Sendable {
        let image: CGImage
    }

    private static func load(_ url: URL, maxPixelSize: Int) async -> NSImage? {
        let loaded = await Task.detached(priority: .utility) { () -> Loaded? in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return Loaded(image: image)
        }.value
        return loaded.map { NSImage(cgImage: $0.image, size: .zero) }
    }
}

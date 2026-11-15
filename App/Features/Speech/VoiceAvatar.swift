import SwiftUI

/// A round badge standing for a voice: its initial on a colour derived from
/// its name, so each voice keeps the same colour everywhere.
struct VoiceAvatar: View {
    let name: String
    var size: CGFloat = 30
    /// A colour to use instead of the name's own.
    var tint: Double?

    private var hue: Double { tint ?? Self.hue(of: name) }

    /// The colour of a script's speaker by their place in it, so that the
    /// speakers of one text never look alike.
    static func hue(ofSpeaker index: Int) -> Double {
        let hues = [0.58, 0.07, 0.78, 0.38, 0.95, 0.48]
        return hues[index % hues.count]
    }

    /// The colour a name stands for, as a hue from 0 to 1.
    static func hue(of name: String) -> Double {
        Double(name.unicodeScalars.reduce(UInt32(11)) { ($0 &* 33) &+ $1.value } % 360) / 360
    }

    var body: some View {
        Circle()
            .fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.50, brightness: 0.92), Color(hue: hue, saturation: 0.72, brightness: 0.62)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.first { $0.isLetter || $0.isNumber } ?? "?").uppercased())
                    .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}

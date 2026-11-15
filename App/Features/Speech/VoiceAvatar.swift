import SwiftUI

/// A round badge standing for a voice: its initial on a colour derived from
/// its name, so each voice keeps the same colour everywhere.
struct VoiceAvatar: View {
    let name: String
    var size: CGFloat = 30

    private var hue: Double {
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

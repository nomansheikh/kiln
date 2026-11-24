import SwiftUI

/// The loudness of the last few seconds as a row of bars, newest on the right.
struct RecordingMeter: View {
    /// Readings from 0 to 1, oldest first.
    let levels: [Double]
    /// How many bars there is room for; missing ones show as silence.
    let length: Int

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<length, id: \.self) { slot in
                let index = slot - (length - levels.count)
                let level = index >= 0 ? levels[index] : 0
                Capsule()
                    .fill(Theme.accent.opacity(index >= 0 ? 0.9 : 0.25))
                    .frame(width: 2.5, height: 3 + 25 * level)
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

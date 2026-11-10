import SwiftUI

/// A thin bar showing the share of this Mac's memory that models may use.
struct SettingsMemoryBar: View {
    /// Between 0 and 1.
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(proxy.size.width * fraction, 8))
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Memory available to models")
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

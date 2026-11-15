import SwiftUI

/// The composer's chip for how fast clips play back.
struct SpeechRateMenu: View {
    @Environment(AppModel.self) private var model

    private static let rates: [Float] = [0.75, 1, 1.25, 1.5, 2]

    var body: some View {
        let speech = model.speech

        Menu {
            ForEach(Self.rates, id: \.self) { rate in
                Button {
                    speech.rate = rate
                } label: {
                    if rate == speech.rate {
                        Label(Self.title(rate), systemImage: "checkmark")
                    } else {
                        Text(verbatim: Self.title(rate))
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "gauge.with.dots.needle.67percent", title: Self.title(speech.rate), active: speech.rate != 1)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .help("Playback speed")
        .accessibilityLabel("Playback speed")
        .accessibilityValue(Self.title(speech.rate))
    }

    /// A speed as a multiple, such as "1.25×".
    private static func title(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "\u{00D7}"
    }
}

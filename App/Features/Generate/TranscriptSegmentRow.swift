import KilnCore
import SwiftUI

/// One stretch of speech: the time it starts at, then its words.
struct TranscriptSegmentRow: View {
    let segment: Transcript.Segment
    /// Whether the recording is playing this segment right now.
    let isCurrent: Bool
    let canPlay: Bool
    let play: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Transcript.clock(segment.start))
                    .font(.system(size: 11.5, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(isCurrent ? Theme.accent : Color.secondary.opacity(0.75))
                    .frame(minWidth: 40, alignment: .trailing)
                Text(segment.text)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
                    .lineSpacing(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `disabled`, which would grey the words of a transcript whose recording is gone.
        .allowsHitTesting(canPlay)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(Transcript.clock(segment.start)). \(segment.text)")
        .accessibilityHint(canPlay ? "Plays the recording from here" : "")
    }

    private var background: Color {
        if isCurrent { return Theme.accent.opacity(0.10) }
        return Color.primary.opacity(hovering && canPlay ? 0.05 : 0)
    }
}

import KilnCore
import SwiftUI

/// The stretches of speech of a transcript, one row each, with a gap where the speaker paused.
struct TranscriptRows: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transcript: Transcript
    /// The row the recording is playing right now.
    var current: Int?
    /// Plays the recording from a row. Nil when there is nothing to play.
    var play: ((Transcript.Segment) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transcript.segments.enumerated()), id: \.offset) { index, segment in
                TranscriptSegmentRow(segment: segment, isCurrent: current == index, canPlay: play != nil) {
                    play?(segment)
                }
                .padding(.top, transcript.startsParagraph(at: index) ? 12 : 0)
                .transition(Motion.rise(reduced: reduceMotion))
            }
        }
        .animation(Motion.layout(reduced: reduceMotion) ?? .easeOut(duration: 0.2), value: transcript.segments.count)
    }
}

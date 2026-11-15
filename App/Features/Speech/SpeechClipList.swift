import KilnCore
import SwiftUI

/// Every clip under the Speech composer, newest first, with the one being
/// made at the top.
struct SpeechClipList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingDelete: AudioItem?

    var body: some View {
        let speech = model.speech
        let clips = model.audio.items

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if speech.isGenerating {
                    SpeechWorkingCard(title: speech.activity.title, voice: speech.voice)
                        .transition(Motion.rise(reduced: reduceMotion))
                }
                ForEach(clips) { clip in
                    SpeechClipCard(clip: clip) { pendingDelete = clip }
                        .transition(Motion.rise(reduced: reduceMotion))
                }
            }
            .animation(Motion.layout(reduced: reduceMotion), value: clips.map(\.id))
            .animation(Motion.layout(reduced: reduceMotion), value: speech.isGenerating)
            .frame(maxWidth: GenerateLayout.columnWidth)
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .clipped()
        // A visible scroller would shift the column off the composer's edges.
        .scrollIndicators(.never)
        .confirmationDialog(
            "Delete this clip?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { clip in
            Button("Delete", role: .destructive) { speech.delete(clip) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The audio file is removed from this Mac. This cannot be undone.")
        }
    }
}

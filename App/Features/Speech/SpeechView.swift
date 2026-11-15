import KilnCore
import SwiftUI

/// The Speech screen: write something, pick a voice, and hear it read aloud.
///
/// It follows the Generate screen: a centred greeting and composer while
/// there is nothing to show, then the composer at the top with every clip
/// under it, newest first. Sending empties the composer, as in a chat; a
/// clip's text can be put back with "Use this text again".
struct SpeechView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let speech = model.speech
        let hasModels = !speech.recipes.isEmpty
        let isEmpty = model.audio.items.isEmpty && !speech.isGenerating

        VStack(spacing: 0) {
            HStack {
                SpeechModelMenu()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)
            // The clip list's scroll view takes clicks above its own frame.
            .zIndex(1)

            if isEmpty {
                Spacer(minLength: 24)
                Text("What do you want to hear?")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            }

            SpeechComposer()
                .disabled(!hasModels)
                .frame(maxWidth: isEmpty ? GenerateLayout.greetingWidth : GenerateLayout.columnWidth)
                .padding(.horizontal, 24)
                .padding(.top, isEmpty ? 0 : 10)

            if isEmpty {
                SpeechStarters()
                    .frame(maxWidth: GenerateLayout.greetingWidth)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .transition(.opacity)
                // More space below than above lifts the group to the optical centre.
                Spacer(minLength: 24)
                Spacer(minLength: 0).frame(maxHeight: 72)
            } else {
                SpeechClipList()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.layout(reduced: reduceMotion), value: isEmpty)
        .alert("Could Not Generate Speech", isPresented: Binding(isPresenting: Bindable(speech).errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(speech.errorMessage ?? "")
        }
    }
}

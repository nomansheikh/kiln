import SwiftUI

/// The Generate screen: a chat-style thread of prompts and images with the
/// composer below it, or a centred greeting while the chat is empty.
///
/// There is one composer in both layouts, so it glides from the centre to the
/// bottom when the first prompt is sent.
struct GenerateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isEmpty = model.generation.turns.isEmpty
        let hasModels = !model.library.installedRecipes.isEmpty

        VStack(spacing: 0) {
            HStack {
                GenerateModelPill()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)
            // The thread's scroll view takes clicks above its own frame, which swallowed
            // the ones meant for the model menu whenever a chat had turns.
            .zIndex(1)

            if isEmpty {
                Spacer(minLength: 24)
                Text("What do you want to create?")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            } else {
                GenerationThread()
                    .transition(.opacity)
            }

            PromptComposer()
                .disabled(isEmpty && !hasModels)
                .frame(maxWidth: isEmpty ? GenerateLayout.greetingWidth : GenerateLayout.columnWidth)
                .padding(.horizontal, 24)
                .padding(.top, isEmpty ? 0 : 6)
                .padding(.bottom, isEmpty ? 0 : 18)

            if isEmpty {
                GenerateStarters()
                    .frame(maxWidth: GenerateLayout.greetingWidth)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .transition(.opacity)
                // More space below than above lifts the group to the optical centre.
                Spacer(minLength: 24)
                Spacer(minLength: 0).frame(maxHeight: 72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.layout(reduced: reduceMotion), value: isEmpty)
    }
}

/// Shared measurements of the Generate screen.
enum GenerateLayout {
    /// Width of the thread and the docked composer.
    static let columnWidth: CGFloat = 760
    /// Width of the composer while it sits under the greeting.
    static let greetingWidth: CGFloat = 640
    /// Longest side of an image in the thread.
    static let imageSide: CGFloat = 440
}

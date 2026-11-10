import SwiftUI

/// The Generate screen: a chat-style thread of prompts and images with the
/// composer below it, or a centred greeting while the thread is empty.
struct GenerateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let isEmpty = model.generation.turns.isEmpty

        VStack(spacing: 0) {
            HStack {
                GenerateModelPill()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)

            if isEmpty {
                GenerateGreeting()
                    .transition(.opacity)
            } else {
                GenerationThread()
                    .transition(.opacity)
                PromptComposer()
                    .frame(maxWidth: GenerateLayout.columnWidth)
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.3), value: isEmpty)
    }
}

/// Shared measurements of the Generate screen.
enum GenerateLayout {
    /// Width of the thread and the docked composer.
    static let columnWidth: CGFloat = 760
    /// Longest side of an image in the thread.
    static let imageSide: CGFloat = 440
}

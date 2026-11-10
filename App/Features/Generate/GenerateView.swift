import SwiftUI

/// The Generate screen: a model selector, the canvas (headline, progress or result)
/// and the prompt composer.
struct GenerateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let generation = model.generation
        // Hero: nothing to show yet, so the composer sits centred under a headline.
        let isHero = generation.latestImage == nil && !generation.phase.isBusy
        let hasModels = !model.library.installedRecipes.isEmpty

        VStack(spacing: 0) {
            HStack {
                GenerateModelPill()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)

            if isHero {
                Spacer(minLength: 24)
                Text("What do you want to create?")
                    .font(Theme.roundedTitle)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            } else {
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                if case .failed(let message) = generation.phase {
                    GenerationErrorCard(message: message) { generation.dismissError() }
                        .transition(.opacity)
                }
                PromptComposer()
                    .disabled(!hasModels && !generation.phase.isBusy)
            }
            .frame(maxWidth: isHero ? 560 : 720)
            .padding(.horizontal, 24)
            .padding(.bottom, isHero ? 0 : 18)

            if isHero {
                Group {
                    if hasModels {
                        PromptSuggestionChips { generation.draft.prompt = $0.prompt }
                    } else {
                        GenerateNoModelsHint { model.selection = .models }
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .transition(.opacity)
                // Slightly more space below than above lifts the group to the optical centre.
                Spacer(minLength: 24)
                Spacer(minLength: 0).frame(maxHeight: 56)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy, value: isHero)
        .animation(.snappy, value: generation.phase.isFailed)
    }

    @ViewBuilder
    private var canvas: some View {
        let generation = model.generation
        if generation.phase.isBusy {
            GenerationProgressView(
                phase: generation.phase,
                prompt: generation.draft.prompt,
                aspectRatio: GenerationImageSize(width: generation.draft.width, height: generation.draft.height).aspectRatio
            )
        } else if let item = generation.latestImage {
            GenerationResultView(item: item)
        }
    }
}

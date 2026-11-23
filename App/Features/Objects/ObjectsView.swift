import KilnCore
import SwiftUI

/// The 3D screen: give it a picture of an object and it builds the object,
/// shown on a turntable you can turn and zoom.
///
/// It follows the other screens: a centred greeting and composer while there
/// is nothing to show, then the object on its stage with the composer under it
/// and earlier objects on a shelf between them.
struct ObjectsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let studio = model.studio
        let isEmpty = studio.current == nil && !studio.isGenerating && studio.proposal == nil

        VStack(spacing: 0) {
            HStack {
                ObjectsModelMenu()
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.leading, 14)
            .zIndex(1)

            if isEmpty {
                Spacer(minLength: 24)
                Text("What do you want to hold in 3D?")
                    .font(.system(size: 28, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 26)
                    .transition(.opacity)
            } else {
                VStack(spacing: 10) {
                    stage
                    if let current = studio.current, !showsWork {
                        ObjectsActions(item: current)
                            .padding(.horizontal, 4)
                    }
                    if model.objects.items.count > 1 || hasWork {
                        ObjectsShelf()
                    }
                }
                .frame(maxWidth: 980)
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .transition(.opacity)
            }

            ObjectsComposer()
                .frame(maxWidth: isEmpty ? GenerateLayout.greetingWidth : GenerateLayout.columnWidth)
                .padding(.horizontal, 24)
                .padding(.top, isEmpty ? 0 : 12)
                .padding(.bottom, isEmpty ? 0 : 18)

            if isEmpty {
                // More space below than above lifts the group to the optical centre.
                Spacer(minLength: 24)
                Spacer(minLength: 0).frame(maxHeight: 72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.layout(reduced: reduceMotion), value: isEmpty)
        .animation(Motion.layout(reduced: reduceMotion), value: studio.isGenerating)
        .animation(Motion.layout(reduced: reduceMotion), value: showsWork)
        .alert("Could Not Make the 3D Object", isPresented: Binding(isPresenting: Bindable(studio).errorMessage)) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(studio.errorMessage ?? "")
        }
    }

    /// True while something is being made or a drawn picture waits for approval.
    private var hasWork: Bool {
        model.studio.isGenerating || model.studio.proposal != nil
    }

    /// True when the stage shows that work and not an earlier object.
    private var showsWork: Bool {
        hasWork && (model.studio.watchesWork || model.studio.current == nil)
    }

    @ViewBuilder
    private var stage: some View {
        let studio = model.studio
        if showsWork, studio.isGenerating {
            ObjectsWorkingView(
                picture: studio.workingPicture, prompt: studio.draft.prompt, activity: studio.activity, startedAt: studio.startedAt
            )
            .transition(.opacity)
        } else if showsWork, let proposal = studio.proposal {
            ObjectsProposalView(item: proposal)
                .transition(.opacity)
        } else if let current = studio.current {
            ObjectsStage(item: current)
                .transition(.opacity)
        }
    }
}

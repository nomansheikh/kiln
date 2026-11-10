import SwiftUI

/// The scrolling conversation. It follows new turns and progress to the bottom.
struct GenerationThread: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let bottomID = "thread-bottom"

    var body: some View {
        let generation = model.generation

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 28) {
                    ForEach(generation.turns) { turn in
                        GenerationTurnView(turn: turn, phase: generation.phase, preview: generation.preview)
                            .transition(Motion.rise(reduced: reduceMotion))
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .animation(Motion.layout(reduced: reduceMotion), value: generation.turns.map(\.id))
                .frame(maxWidth: GenerateLayout.columnWidth)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .clipped()
            // A visible scroller would shift the column off the composer's edges.
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
            .onChange(of: generation.turns) {
                withAnimation(.snappy) { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
        }
    }
}

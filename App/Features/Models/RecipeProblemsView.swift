import KilnCore
import SwiftUI

/// A collapsible warning card listing the recipe files that failed to load.
struct RecipeProblemsView: View {
    let problems: [RecipeStore.LoadFailure]
    @State private var isExpanded = false

    private var title: String {
        problems.count == 1 ? "1 recipe could not be loaded" : "\(problems.count) recipes could not be loaded"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isExpanded {
                problemList
            }
        }
        .card(padding: 12)
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var problemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(problems.enumerated()), id: \.element.file) { index, problem in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(problem.file.lastPathComponent)
                        .font(.caption.monospaced().weight(.medium))
                    Text(problem.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
        }
        .modelsInsetSurface()
    }
}

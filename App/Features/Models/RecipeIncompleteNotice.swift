import SwiftUI

/// Shown on a one-file model that is really just a part of a larger model:
/// says why it cannot be used and offers to remove it from the list.
struct RecipeIncompleteNotice: View {
    /// Removes the entry, keeping any file a full recipe still needs.
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "puzzlepiece.extension")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("This is one part of a model, not a whole one, so it cannot generate images by itself. A recipe lists every part a model needs.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let guide = URL(string: "https://github.com/nomansheikh/kiln/blob/main/docs/recipes.md") {
                    Link("How recipes work", destination: guide)
                }
            }
            .font(.callout)
            Spacer(minLength: 8)
            Button("Remove", action: remove)
                .buttonStyle(SoftButtonStyle())
                .help("Remove this entry. A file that a recipe still needs is kept.")
        }
    }
}

import SwiftUI

/// The Download button of a recipe that is not on this Mac yet. It steps back to the
/// quiet style, with a warning tooltip, when the model is too large for this Mac.
struct RecipeDownloadButton: View {
    let isTooLarge: Bool
    let action: () -> Void

    var body: some View {
        if isTooLarge {
            button
                .buttonStyle(SoftButtonStyle())
                .fixedSize()
                .help("This model needs more memory than this Mac has and may not run.")
        } else {
            button
                .buttonStyle(AccentButtonStyle())
                .fixedSize()
        }
    }

    private var button: some View {
        Button(action: action) {
            Label("Download", systemImage: "arrow.down")
        }
    }
}

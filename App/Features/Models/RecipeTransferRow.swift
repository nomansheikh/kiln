import SwiftUI

/// A progress bar with its controls beside it and a caption underneath.
struct RecipeTransferRow<Buttons: View>: View {
    /// Progress from 0 to 1, or nil for an indeterminate bar.
    let value: Double?
    let caption: String
    @ViewBuilder let buttons: Buttons

    var body: some View {
        // The buttons share a row with the bar so they centre on it; the caption sits below both.
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                ProgressView(value: value)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 6) {
                    buttons
                }
                .fixedSize()
            }
            Text(caption)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(caption)
        }
    }
}

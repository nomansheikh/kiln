import SwiftUI

/// The red banner shown in a recipe card when its download failed.
struct RecipeTransferFailure: View {
    let message: String
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label {
                Text(message)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ModelsIconButton(systemImage: "arrow.clockwise", help: "Retry download", action: retry)
                ModelsIconButton(systemImage: "xmark", help: "Dismiss", action: dismiss)
            }
            .fixedSize()
        }
        .padding(10)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

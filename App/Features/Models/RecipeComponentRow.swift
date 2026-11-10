import KilnCore
import SwiftUI

/// One file of a recipe: its role, file name and size.
struct RecipeComponentRow: View {
    let component: ModelRecipe.Component

    private var roleTitle: String {
        component.role.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(roleTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            Text(component.file)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .help("\(component.repo)/\(component.file)")
            Spacer(minLength: 8)
            if let size = component.sizeBytes {
                Text(size.formatted(.byteCount(style: .file)))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

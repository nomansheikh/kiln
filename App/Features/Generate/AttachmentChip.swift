import KilnCore
import SwiftUI

/// An attached file that is not a picture, shown by its kind and name.
struct AttachmentChip: View {
    let url: URL

    var body: some View {
        let kind = AttachmentLibrary.kind(of: url)

        HStack(spacing: 8) {
            Image(systemName: kind?.symbolName ?? "doc")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(verbatim: AttachmentLibrary.displayName(of: url))
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 42)
        .frame(maxWidth: 320, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Attached file: \(AttachmentLibrary.displayName(of: url))")
    }
}

import SwiftUI

/// Small rounded label for metadata such as size or quantization.
struct Pill: View {
    let text: String
    var systemImage: String?
    var tint: Color?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint ?? .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((tint ?? .primary).opacity(tint == nil ? 0.07 : 0.14), in: Capsule())
    }
}

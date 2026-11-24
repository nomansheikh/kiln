import SwiftUI

/// The frame a transcript sits in, finished or still being written: a header with
/// a thin bar under it, the rows, and an optional line of actions.
struct TranscriptCard<Leading: View, Rows: View, Footer: View>: View {
    let title: String
    let subtitle: String
    /// How full the bar under the header is, from 0 to 1: playback, or the work done.
    let fraction: Double
    @ViewBuilder let leading: Leading
    @ViewBuilder let rows: Rows
    @ViewBuilder let footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                leading
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.hairline)
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 2)
            .animation(.linear(duration: 0.12), value: fraction)
            .accessibilityHidden(true)

            rows
                .padding(.horizontal, 6)
                .padding(.vertical, 8)

            footer
        }
        .frame(maxWidth: 640, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
    }
}

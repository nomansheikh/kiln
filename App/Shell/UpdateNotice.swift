import KilnCore
import SwiftUI

/// The sidebar's quiet note that a newer version of Kiln exists, with a link
/// to its release page and a way to hide it until the next version.
struct UpdateNotice: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let release: PublishedRelease

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Kiln \(release.version.description) is available")
                    .fixedSize(horizontal: false, vertical: true)
                Button("View release") { openURL(release.pageURL) }
                    .buttonStyle(PressableButtonStyle(scale: 0.97))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .focusable(false)
                    .help("Open the release page on GitHub")
            }
            Spacer(minLength: 4)
            RoundIconButton(systemImage: "xmark", help: "Hide until the next version") {
                model.updates.dismiss()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

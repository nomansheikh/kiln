import SwiftUI

/// The file attached to the prompt being written and a way to remove it.
/// An image also shows how much it may change.
struct ComposerAttachment: View {
    let url: URL
    @Binding var strength: EditStrength
    let remove: () -> Void

    var body: some View {
        if AttachmentLibrary.kind(of: url) == .image {
            imageAttachment
        } else {
            AttachmentChip(url: url)
                .overlay(alignment: .topTrailing) { removeButton(label: "Remove attached file") }
        }
    }

    private var imageAttachment: some View {
        HStack(spacing: 10) {
            Thumbnail(url: url, maxPixelSize: 160)
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline))
                .overlay(alignment: .topTrailing) { removeButton(label: "Remove attached image") }

            VStack(alignment: .leading, spacing: 4) {
                Text("Editing this image")
                    .font(.callout.weight(.medium))
                strengthMenu
            }
            Spacer(minLength: 0)
        }
    }

    private func removeButton(label: String) -> some View {
        Button(action: remove) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.window)
                .frame(width: 16, height: 16)
                .background(Color.primary, in: Circle())
        }
        .buttonStyle(PressableButtonStyle(scale: 0.85))
        .focusable(false)
        .offset(x: 5, y: -5)
        .help("Remove")
        .accessibilityLabel(label)
    }

    private var strengthMenu: some View {
        Menu {
            ForEach(EditStrength.allCases) { option in
                Button {
                    strength = option
                } label: {
                    if option == strength {
                        Label("\(option.title): \(option.explanation)", systemImage: "checkmark")
                    } else {
                        Text("\(option.title): \(option.explanation)")
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "dial.medium", title: "\(strength.title) change")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("How much the image may change")
    }
}

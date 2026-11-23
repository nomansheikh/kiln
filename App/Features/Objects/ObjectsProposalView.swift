import KilnCore
import SwiftUI

/// The stage while a picture drawn from a description waits to be approved.
/// Making the object takes minutes, so it does not start on a picture nobody looked at.
struct ObjectsProposalView: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem

    var body: some View {
        let studio = model.studio
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            StageBackdrop()
            VStack(spacing: 20) {
                Thumbnail(url: item.url, maxPixelSize: 1024)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 380, maxHeight: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.18)))
                    .shadow(color: .black.opacity(0.28), radius: 26, y: 16)
                VStack(spacing: 4) {
                    Text("Make this into a 3D object?")
                        .font(.system(size: 17, weight: .semibold))
                    Text("It works best when the whole object is in view with nothing behind it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    Button("Draw Another") { studio.redrawProposal() }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(studio.isEngineBusyElsewhere())
                    Button {
                        studio.acceptProposal()
                    } label: {
                        Label("Make It 3D", systemImage: "cube")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(studio.isEngineBusyElsewhere() || studio.selectedRecipe == nil)
                }
                .controlSize(.large)
            }
            .padding(24)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .overlay(alignment: .topTrailing) {
            StageButton(systemImage: "xmark", help: "Leave this picture", hintAlignment: .bottomTrailing) { studio.dismissProposal() }
                .padding(12)
        }
    }
}

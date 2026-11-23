import KilnCore
import SwiftUI
import UniformTypeIdentifiers

/// The 3D screen's composer: the picture an object is made from, the chips
/// for its settings and the send button, in the same shape as the other screens'.
struct ObjectsComposer: View {
    @Environment(AppModel.self) private var model
    @State private var isPickingPicture = false
    @State private var isDropTarget = false
    @State private var showsAdvanced = false
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var studio = model.studio
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        HStack(alignment: .center, spacing: 12) {
            pictureWell
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if studio.draft.image == nil {
                        // Return sends, as in the other composers.
                        TextField(title, text: $studio.draft.prompt, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .lineLimit(1...3)
                            .focused($isFocused)
                            .onSubmit(send)
                    } else {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                    }
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    detailMenu
                    Button { showsAdvanced.toggle() } label: {
                        ComposerChip(systemImage: "slider.horizontal.3", title: "Advanced", active: studio.draft.hasCustomSettings || !studio.draft.randomSeed)
                    }
                    .buttonStyle(.plain)
                    .pointerCursor()
                    .focusable(false)
                    .hint("Sampling, cut-out, colour size and seed")
                    .popover(isPresented: $showsAdvanced, arrowEdge: .top) {
                        ObjectsAdvancedSettings().environment(model)
                    }
                    if studio.draft.image == nil, studio.pictureRecipes.count > 1 {
                        pictureModelMenu
                    }
                    Spacer(minLength: 8)
                    PromptSendButton(isBusy: studio.isGenerating, action: send)
                        .disabled(!studio.isGenerating && !studio.canGenerate)
                        .hint(sendHelp, alignment: .topTrailing)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(isDropTarget ? Theme.accent : Theme.hairline, lineWidth: isDropTarget ? 2 : 1))
        .composerGlow(isWorking: studio.isGenerating, isFocused: isFocused)
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTarget, perform: drop)
        .fileImporter(isPresented: $isPickingPicture, allowedContentTypes: [.image]) { result in
            if case .success(let file) = result { studio.setPicture(file) }
        }
        .animation(.snappy(duration: 0.2), value: studio.draft.image)
    }

    /// The picture, or the place to put one.
    private var pictureWell: some View {
        let studio = model.studio
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { isPickingPicture = true } label: {
            ZStack {
                if let picture = studio.draft.image {
                    Thumbnail(url: picture, maxPixelSize: 320)
                } else {
                    Theme.card
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 20, weight: .regular))
                        Text("Choose")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline))
            .contentShape(shape)
        }
        .overlay(alignment: .topTrailing) {
            if studio.draft.image != nil {
                Button { studio.draft.image = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.window)
                        .frame(width: 16, height: 16)
                        .background(Color.primary, in: Circle())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.85))
                .focusable(false)
                .offset(x: 5, y: -5)
                .hint("Remove the picture")
            }
        }
        .buttonStyle(PressableButtonStyle(scale: 0.97))
        .pointerCursor()
        .hint(studio.draft.image == nil ? "Choose a picture, or drop one here" : "Choose another picture", alignment: .topLeading)
    }

    private var detailMenu: some View {
        let studio = model.studio
        return Menu {
            ForEach(MeshSettings.Detail.allCases) { option in
                Button {
                    studio.draft.detail = option
                } label: {
                    let text = "\(option.title): \(option.explanation)"
                    if option == studio.draft.detail {
                        Label(text, systemImage: "checkmark")
                    } else {
                        Text(text)
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "square.stack.3d.up", title: studio.draft.detail.title, active: studio.draft.detail != .standard)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .hint("How finely the object is worked out")
        .accessibilityValue(studio.draft.detail.title)
    }

    /// Which image model draws the picture, when there is more than one.
    private var pictureModelMenu: some View {
        let studio = model.studio
        return Menu {
            ForEach(studio.pictureRecipes) { recipe in
                Button {
                    studio.pictureRecipeID = recipe.id
                } label: {
                    if recipe.id == studio.pictureRecipe?.id {
                        Label(recipe.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: recipe.name)
                    }
                }
            }
        } label: {
            ComposerChip(systemImage: "photo", title: studio.pictureRecipe?.name ?? "Picture")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .pointerCursor()
        .menuIndicator(.hidden)
        .focusable(false)
        .fixedSize()
        .hint("The model that draws the picture")
    }

    private var title: String {
        let studio = model.studio
        if studio.draft.image != nil { return "Ready to make it 3D" }
        if studio.pictureRecipe == nil { return "Add a picture of one object" }
        return "Describe an object, or add a picture of one"
    }

    private var hint: String {
        let studio = model.studio
        if studio.recipes.isEmpty { return "Download a model that makes 3D objects first." }
        if studio.draft.image == nil {
            if studio.isGenerating { return "It will wait here until the stage is free." }
            if let artist = studio.pictureRecipe, !studio.draft.prompt.isEmpty {
                return "\(artist.name) draws a picture first, for you to approve."
            }
            return studio.pictureRecipe == nil
                ? "A single object on a plain background works best. Drop a picture here, or choose one."
                : "A picture of a single object on a plain background works best. From words, a picture is drawn first."
        }
        var parts = [studio.draft.detail.explanation]
        if let memory = MeshDraft.measuredMemoryGB(for: studio.draft.detail) {
            parts.append("about \(memory.formatted()) GB of memory")
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var sendHelp: String {
        let studio = model.studio
        if studio.isGenerating { return "Stop (\u{2318}.)" }
        if studio.canGenerate {
            return studio.nextStep == .picture ? "Draw a picture of it (\u{21A9})" : "Make the 3D object (\u{21A9})"
        }
        if studio.isEngineBusyElsewhere() { return "Another model is working. Wait for it to finish." }
        if studio.selectedRecipe == nil { return "Download a model that makes 3D objects first" }
        return studio.pictureRecipe == nil ? "Add a picture first" : "Describe an object or add a picture first"
    }

    private func send() {
        let studio = model.studio
        if studio.isGenerating { studio.cancel() } else { studio.generate() }
    }

    /// Takes a dropped image file, or an image dragged out of another app.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.studio.setPicture(url) }
            }
            return true
        }
        return false
    }
}

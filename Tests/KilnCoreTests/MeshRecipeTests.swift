import Foundation
import Testing
@testable import KilnCore

@Suite struct MeshRecipeTests {
    private func recipe(_ files: [String]) -> ModelRecipe {
        ModelRecipe(
            id: "shaper", name: "Shaper", engine: TrellisCppEngine.engineID,
            components: files.enumerated().map { index, file in
                .init(role: index == 0 ? .model : .support, repo: "owner/name", file: file)
            },
            output: .mesh, accepts: [.image], defaults: nil
        )
    }

    private var trellis: ModelRecipe { recipe(["q4/ss_flow.gguf", "q4/tex_flow_512.gguf", "q4/tex_flow_1024.gguf"]) }
    private var pixal3d: ModelRecipe { recipe(["pixal3d_ss_flow.gguf", "pixal3d_tex_flow_1024.gguf", "q4/dinov3.gguf"]) }

    @Test func theFamilyIsReadFromTheMainFilesName() {
        #expect(trellis.meshFamily == "trellis")
        #expect(pixal3d.meshFamily == "pixal3d")
    }

    @Test func aFolderNameDoesNotMakeAFamily() {
        #expect(recipe(["pixal3d_files/ss_flow.gguf"]).meshFamily == "trellis")
    }

    @Test func standardDetailNeedsItsOwnTextureFile() {
        #expect(trellis.meshDetails == [.standard, .fine, .ultra])
        #expect(pixal3d.meshDetails == [.fine, .ultra])
    }

    @Test func choosingAModelDropsADetailItDoesNotHave() {
        var draft = MeshDraft()
        draft.detail = .standard
        draft.select(pixal3d)
        #expect(draft.recipeID == "shaper")
        #expect(draft.detail == .fine)
    }

    @Test func choosingAModelKeepsADetailItHas() {
        var draft = MeshDraft()
        draft.detail = .ultra
        draft.select(pixal3d)
        #expect(draft.detail == .ultra)
        draft.select(trellis)
        #expect(draft.detail == .ultra)
    }
}

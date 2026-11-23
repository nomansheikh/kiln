import Foundation
import KilnCore

/// What the 3D screen's store needs: models that make objects, a picture and an object.
extension StoreFixture {
    /// A model that makes 3D objects at every level of detail.
    static let shaper = meshRecipe("shaper", files: ["ss_flow.gguf", "tex_flow_512.gguf", "tex_flow_1024.gguf"])
    /// One with no texture file for standard detail, as Pixal3D has none.
    static let fineShaper = meshRecipe("fine-shaper", files: ["pixal3d_ss_flow.gguf", "pixal3d_tex_flow_1024.gguf"])

    static let object = GeneratedMesh(glb: Data("glTF, as far as a store can tell".utf8))

    private static func meshRecipe(_ id: String, files: [String]) -> ModelRecipe {
        ModelRecipe(
            id: id, name: id.capitalized, engine: TrellisCppEngine.engineID,
            components: files.enumerated().map { index, file in
                .init(role: index == 0 ? .model : .support, repo: "owner/\(id)", file: file, revision: "abc",
                      sizeBytes: 2_000_000_000, sha256: checksum)
            },
            output: .mesh, accepts: [.image], defaults: nil
        )
    }

    func objectsStore() -> ObjectsStore {
        ObjectsStore(
            library: library, objects: MeshLibrary(store: MeshStore(directory: root.appendingPathComponent("objects"))),
            gallery: gallery, attachments: AttachmentLibrary(directory: root.appendingPathComponent("attachments")),
            engine: engine
        )
    }

    /// A real PNG to make an object from.
    func pictureFile() throws -> URL {
        let record = GenerationRecord(recipeID: "r", recipeName: "R", request: GenerationRequest(prompt: "p"), durationSeconds: nil)
        let file = root.appendingPathComponent("picture-\(UUID().uuidString).png")
        try ImageCodec.pngData(for: Self.picture, record: record).write(to: file)
        return file
    }
}

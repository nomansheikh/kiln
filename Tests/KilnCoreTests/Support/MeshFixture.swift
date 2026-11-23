import Foundation
@testable import KilnCore

/// A models folder with one installed recipe that makes 3D objects, a picture
/// to give it, and fake helpers to run it against.
struct MeshFixture {
    let root: URL
    let storage: ModelStorage
    let recipe: ModelRecipe
    let picture: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-mesh-tests-\(UUID().uuidString)")
        storage = ModelStorage(root: root.appendingPathComponent("models"))
        recipe = ModelRecipe(
            id: "shaper", name: "Shaper", engine: TrellisCppEngine.engineID,
            components: [
                .init(role: .model, repo: "owner/name", file: "q4/ss_flow.gguf"),
                .init(role: .support, repo: "owner/name", file: "q4/dinov3.gguf"),
            ],
            output: .mesh, accepts: [.image], defaults: nil
        )
        for component in recipe.components {
            let file = storage.url(for: component)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: file)
        }
        picture = try FileFixtures().image()
    }

    /// An engine whose helper is a shell script. `body` runs once per request,
    /// with `$line` holding the request and `$output` the output path.
    func engine(onShape body: String, onCancel: String = ":", grace: Duration = .seconds(3)) throws -> TrellisCppEngine {
        let script = """
        #!/bin/sh
        echo '{"type":"ready","version":"test","commit":""}'
        while IFS= read -r line; do
          case "$line" in
            *'"type":"cancel"'*)
              \(onCancel)
              ;;
            *'"type":"shape"'*)
              output=$(printf '%s' "$line" | sed -E 's/.*"output":"([^"]*)".*/\\1/')
              image=$(printf '%s' "$line" | sed -E 's/.*"image":"([^"]*)".*/\\1/')
              \(body)
              ;;
          esac
        done
        """
        let helper = root.appendingPathComponent("helper-\(UUID().uuidString).sh")
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return TrellisCppEngine(
            helperURL: helper, storage: storage, scratchDirectory: root.appendingPathComponent("scratch"), cancelGracePeriod: grace
        )
    }

    /// Writes a file that starts like a GLB, and the engine's leftover beside it.
    let success = """
    echo '{"type":"progress","stage":"step","completed":12,"total":84}'
    printf 'glTF0000000000000000rest' > "$output"
    printf 'points' > "${output%.glb}.ply"
    echo "{\\"type\\":\\"object\\",\\"path\\":\\"$output\\"}"
    echo '{"type":"idle"}'
    """
}

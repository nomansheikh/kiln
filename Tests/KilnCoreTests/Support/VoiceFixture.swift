import Foundation
@testable import KilnCore

/// A models folder with one installed text-to-speech recipe and fake helpers
/// to run it against.
struct VoiceFixture {
    let root: URL
    let storage: ModelStorage
    let recipe: ModelRecipe

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-voice-tests-\(UUID().uuidString)")
        storage = ModelStorage(root: root.appendingPathComponent("models"))
        recipe = ModelRecipe(
            id: "voice",
            name: "Voice",
            engine: AudioCppEngine.engineID,
            components: [
                .init(role: .model, repo: "owner/name", file: "english/model.gguf"),
                .init(role: .voice, repo: "owner/name", file: "english/embeddings/alba.safetensors"),
                .init(role: .voice, repo: "owner/name", file: "english/embeddings/george.safetensors"),
            ],
            output: .audio,
            defaults: nil,
            speech: .init(family: "pocket_tts", voice: "george")
        )
        for component in recipe.components {
            let file = storage.url(for: component)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: file)
        }
    }

    /// An engine whose helper is a shell script. `body` runs once per speak
    /// request, with `$line` holding the request and `$output` the output path.
    func engine(onSpeak body: String, grace: Duration = .seconds(3)) throws -> AudioCppEngine {
        let script = """
        #!/bin/sh
        echo '{"type":"ready","version":"test","commit":""}'
        while IFS= read -r line; do
          case "$line" in
            *'"type":"speak"'*)
              output=$(printf '%s' "$line" | sed -E 's/.*"output":"([^"]*)".*/\\1/')
              \(body)
              ;;
          esac
        done
        """
        let helper = root.appendingPathComponent("helper-\(UUID().uuidString).sh")
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        return AudioCppEngine(
            helperURL: helper,
            storage: storage,
            scratchDirectory: root.appendingPathComponent("scratch"),
            cancelGracePeriod: grace
        )
    }

    /// Two frames of mono sound: eight bytes, the way the real helper writes them.
    let success = """
    echo '{"type":"loading"}'
    echo '{"type":"progress","stage":"speaking","completed":0,"total":0}'
    printf 'abcdefgh' > "$output"
    echo "{\\"type\\":\\"audio\\",\\"path\\":\\"$output\\",\\"sample_rate\\":24000,\\"channels\\":1,\\"frames\\":2}"
    echo '{"type":"idle"}'
    """
}

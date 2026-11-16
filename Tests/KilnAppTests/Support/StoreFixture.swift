import Foundation
import KilnCore

/// The app's stores over a folder of their own, with an engine and a downloader
/// that do no real work. Nothing touches the user's models, clips or chats.
@MainActor
struct StoreFixture {
    static let checksum = String(repeating: "ab", count: 32)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-app-tests-\(UUID().uuidString)")
    let engine = FakeEngine()
    let downloader = InstantDownloader()
    let storage: ModelStorage
    let recipeStore: RecipeStore
    let library: ModelLibrary
    let gallery: GalleryLibrary
    let audio: AudioLibrary
    let chats: ChatLibrary
    let voices: VoiceLibrary

    /// An image model, a model that reads text aloud in the voices "alba" and
    /// "george", one that copies voices, and one that writes speech down.
    static let image = recipe("picture", role: .checkpoint, file: "picture.safetensors", output: nil, defaults: .init(
        steps: 8, cfg: 1, sampler: "lcm", width: 768, height: 512
    ))
    static let voice = recipe("voice", file: "voice.gguf", output: .audio, speech: .init(
        family: "pocket_tts", voices: ["alba", "george"], voice: "george"
    ))
    static let copier = recipe("copier", file: "copier.gguf", output: .audio, speech: .init(
        family: "omnivoice", reference: .required
    ))
    static let writer = recipe("writer", file: "ggml-writer.bin", output: .text, accepts: [.audio], engine: "whisper.cpp")

    /// - Parameter installed: The recipes whose files are on disk from the start.
    init(recipes: [ModelRecipe] = [image, voice, copier, writer], installed: [ModelRecipe] = [image, voice, copier, writer]) throws {
        storage = ModelStorage(root: root.appendingPathComponent("models"))
        recipeStore = RecipeStore(
            bundledDirectory: root.appendingPathComponent("bundled"), userDirectory: root.appendingPathComponent("user")
        )
        try FileManager.default.createDirectory(at: recipeStore.bundledDirectory, withIntermediateDirectories: true)
        for recipe in recipes {
            try JSONEncoder().encode(recipe).write(to: recipeStore.bundledDirectory.appendingPathComponent("\(recipe.id).json"))
        }
        for component in installed.flatMap(\.components) {
            let file = storage.url(for: component)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: file)
        }
        library = ModelLibrary(
            storage: storage, recipeStore: recipeStore, hub: HFClient(),
            downloads: DownloadManager(storage: storage, downloader: downloader, freeSpace: { _ in nil })
        )
        gallery = GalleryLibrary(store: GalleryStore(directory: root.appendingPathComponent("gallery")))
        audio = AudioLibrary(store: AudioStore(directory: root.appendingPathComponent("audio")))
        chats = ChatLibrary(store: ChatStore(directory: root.appendingPathComponent("chats")))
        voices = VoiceLibrary(store: VoiceStore(directory: root.appendingPathComponent("voices")))
    }

    func generationStore() -> GenerationStore {
        GenerationStore(
            library: library, gallery: gallery, audio: audio, chats: chats,
            attachments: AttachmentLibrary(directory: root.appendingPathComponent("attachments")), engine: engine
        )
    }

    func speechStore() -> SpeechStore {
        SpeechStore(library: library, audio: audio, voices: voices, engine: engine)
    }

    /// A tenth of a second of silence.
    static let sound = GeneratedAudio(sampleRate: 24_000, channels: 1, samples: Data(count: 2_400 * 4))
    static let picture = GeneratedImage(width: 2, height: 1, channels: 3, pixels: Data(repeating: 128, count: 6))

    /// A recording to add as a voice.
    func recording() throws -> URL {
        let file = root.appendingPathComponent("recording-\(UUID().uuidString).wav")
        try Self.sound.wavData().write(to: file)
        return file
    }

    /// Large enough for a single file to count as a whole model. Only declared: the files written are tiny.
    private static let declaredSize: Int64 = 2_000_000_000

    private static func recipe(
        _ id: String, role: ModelRecipe.ComponentRole = .model, file: String, output: MediaKind?, accepts: [MediaKind]? = nil,
        engine: String = "audio.cpp", defaults: ModelRecipe.ImageDefaults? = nil, speech: ModelRecipe.SpeechDefaults? = nil
    ) -> ModelRecipe {
        ModelRecipe(
            id: id, name: id.capitalized, engine: output == nil ? "sd.cpp" : engine,
            components: [.init(role: role, repo: "owner/\(id)", file: file, revision: "abc", sizeBytes: declaredSize, sha256: checksum)],
            output: output, accepts: accepts, defaults: defaults, speech: speech
        )
    }
}

/// Writes each file at once, as if it had been downloaded.
struct InstantDownloader: FileDownloading {
    func download(_ item: DownloadItem, onEvent: @escaping @Sendable (TransferEvent) -> Void) async throws {
        try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: item.destination)
    }
}

/// Waits for something a store does in a task of its own. Fails the test when it never happens.
@MainActor
func waitUntil(_ what: String, _ condition: () -> Bool) async throws {
    for _ in 0..<2_000 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw NeverHappened(what: what)
}

struct NeverHappened: Error, CustomStringConvertible {
    let what: String
    var description: String { "Timed out waiting until \(what)." }
}

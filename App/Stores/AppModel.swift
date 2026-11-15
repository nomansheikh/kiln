import Foundation
import KilnCore
import Observation

/// The root of the app's state. It owns one store per feature and the few
/// actions that touch more than one of them.
@MainActor
@Observable
final class AppModel {
    var selection: SidebarItem? = .generate

    let library: ModelLibrary
    let generation: GenerationStore
    let speech: SpeechStore
    let gallery: GalleryLibrary
    let audio: AudioLibrary
    let chats: ChatLibrary
    let account: HubAccount

    init() {
        let support = URL.applicationSupportDirectory.appendingPathComponent("Kiln", isDirectory: true)
        let tokenStore = KeychainTokenStore()
        #if DEBUG
        let storage = ModelStorage(root: DebugSnapshot.modelsDirectory ?? ModelStorage.defaultRoot)
        #else
        let storage = ModelStorage(root: ModelStorage.defaultRoot)
        #endif
        let hub = HFClient(token: { tokenStore.read() })

        let library = ModelLibrary(
            storage: storage,
            recipeStore: RecipeStore(
                bundledDirectory: Bundle.main.resourceURL?.appendingPathComponent("recipes")
                    ?? support.appendingPathComponent("bundled"),
                userDirectory: support.appendingPathComponent("recipes", isDirectory: true),
                remoteDirectory: Self.remoteRecipesDirectory,
                catalogDirectory: Bundle.main.resourceURL?.appendingPathComponent("catalog")
            ),
            hub: hub,
            downloads: DownloadManager(
                storage: storage,
                downloader: FileDownloader { url in HFClient.authorizationHeader(for: url, token: tokenStore.read()) }
            )
        )
        #if DEBUG
        let galleryDirectory = DebugSnapshot.galleryDirectory ?? GalleryStore.defaultDirectory
        #else
        let galleryDirectory = GalleryStore.defaultDirectory
        #endif
        let gallery = GalleryLibrary(store: GalleryStore(directory: galleryDirectory))
        #if DEBUG
        let audioDirectory = DebugSnapshot.audioDirectory ?? DebugSnapshot.sampleAudioDirectory ?? AudioStore.defaultDirectory
        #else
        let audioDirectory = AudioStore.defaultDirectory
        #endif
        let audio = AudioLibrary(store: AudioStore(directory: audioDirectory))
        let chats = ChatLibrary(store: ChatStore(directory: ChatStore.defaultDirectory))
        let engine = EngineRouter(Self.engines(storage: storage))
        let generation = GenerationStore(
            library: library,
            gallery: gallery,
            audio: audio,
            chats: chats,
            attachments: AttachmentLibrary(directory: AttachmentLibrary.defaultDirectory),
            engine: engine
        )

        self.library = library
        self.gallery = gallery
        self.audio = audio
        self.chats = chats
        self.generation = generation
        #if DEBUG
        let voicesDirectory = DebugSnapshot.voicesDirectory ?? VoiceStore.defaultDirectory
        #else
        let voicesDirectory = VoiceStore.defaultDirectory
        #endif
        let speech = SpeechStore(
            library: library, audio: audio, voices: VoiceLibrary(store: VoiceStore(directory: voicesDirectory)), engine: engine
        )
        self.speech = speech
        // The engines hold one model in memory, so only one screen generates at a time.
        generation.isEngineBusyElsewhere = { [weak speech] in speech?.isUsingEngine ?? false }
        speech.isEngineBusyElsewhere = { [weak generation] in generation?.phase.isBusy ?? false }
        account = HubAccount(tokenStore: tokenStore, hub: hub)

        library.onInstalledChange = { [weak generation, weak speech] in
            generation?.selectDefaultRecipeIfNeeded()
            speech?.selectDefaultRecipeIfNeeded()
        }
        refreshRecipeCatalogIfDue()
    }

    /// Every engine under the id recipes use for it, each with its helper inside the app.
    private static func engines(storage: ModelStorage) -> [String: any InferenceEngine] {
        func helper(_ name: String) -> URL {
            Bundle.main.url(forAuxiliaryExecutable: name)
                ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
        }
        return [
            StableDiffusionCppEngine.engineID: StableDiffusionCppEngine(helperURL: helper("kiln-engine"), storage: storage),
            WhisperCppEngine.engineID: WhisperCppEngine(helperURL: helper("kiln-whisper"), storage: storage),
            AudioCppEngine.engineID: AudioCppEngine(helperURL: helper("kiln-audio"), storage: storage),
        ]
    }

    // MARK: - Recipe updates

    private static var remoteRecipesDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Kiln/recipes-remote", isDirectory: true)
    }

    /// Fetches newly published recipes at most once a day. Failing, for example
    /// offline, changes nothing: the bundled and cached recipes keep working.
    private func refreshRecipeCatalogIfDue() {
        let key = "recipeCatalogRefreshedAt"
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 60 * 60 else { return }
        Task {
            guard (try? await RecipeCatalog(cacheDirectory: Self.remoteRecipesDirectory).refresh()) != nil else { return }
            UserDefaults.standard.set(Date(), forKey: key)
            library.reloadRecipes()
        }
    }

    // MARK: - Actions across features

    /// Opens Generate with a new, empty chat.
    func newChat() {
        generation.startOver()
        selection = .generate
    }

    /// Opens a saved chat on the Generate screen.
    func open(_ chat: Chat) {
        generation.open(chat)
        selection = .generate
    }

    /// Deletes a chat, leaving its images in the Gallery.
    func delete(_ chat: Chat) {
        chats.delete(chat.id)
        if generation.chatID == chat.id {
            generation.startOver()
        }
    }

    /// Opens Generate with a past image's settings filled in.
    func reuseSettings(of item: GalleryItem) {
        generation.reuseSettings(of: item)
        selection = .generate
    }

    func deleteGalleryItem(_ item: GalleryItem) throws {
        try gallery.delete(item)
        generation.forget(item)
    }

    /// Opens Models showing only the models for one task.
    func browseModels(for task: ModelTask) {
        UserDefaults.standard.set(task.rawValue, forKey: "models.taskFilter")
        selection = .models
    }

    /// Opens the screen a model is used on, with the model selected: Speech for
    /// one that reads text aloud, the chat for everything else.
    func use(_ recipe: ModelRecipe) {
        if recipe.task == .textToSpeech {
            speech.selectRecipe(recipe)
            selection = .speech
        } else {
            generation.selectRecipe(recipe)
            selection = .generate
        }
    }
}

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
    let gallery: GalleryLibrary
    let chats: ChatLibrary
    let account: HubAccount

    init() {
        let support = URL.applicationSupportDirectory.appendingPathComponent("Kiln", isDirectory: true)
        let tokenStore = KeychainTokenStore()
        let storage = ModelStorage(root: ModelStorage.defaultRoot)
        let hub = HFClient(token: { tokenStore.read() })

        let library = ModelLibrary(
            storage: storage,
            recipeStore: RecipeStore(
                bundledDirectory: Bundle.main.resourceURL?.appendingPathComponent("recipes")
                    ?? support.appendingPathComponent("bundled"),
                userDirectory: support.appendingPathComponent("recipes", isDirectory: true),
                remoteDirectory: Self.remoteRecipesDirectory
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
        let chats = ChatLibrary(store: ChatStore(directory: ChatStore.defaultDirectory))
        let generation = GenerationStore(
            library: library,
            gallery: gallery,
            chats: chats,
            attachments: AttachmentLibrary(directory: AttachmentLibrary.defaultDirectory),
            engine: StableDiffusionCppEngine(
                helperURL: Bundle.main.url(forAuxiliaryExecutable: "kiln-engine")
                    ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/kiln-engine"),
                storage: storage
            )
        )

        self.library = library
        self.gallery = gallery
        self.chats = chats
        self.generation = generation
        account = HubAccount(tokenStore: tokenStore, hub: hub)

        library.onInstalledChange = { [weak generation] in
            generation?.selectDefaultRecipeIfNeeded()
        }
        refreshRecipeCatalogIfDue()
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
    func newImage() {
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

    /// Uses a model on the Generate screen.
    func use(_ recipe: ModelRecipe) {
        generation.selectRecipe(recipe)
        selection = .generate
    }
}

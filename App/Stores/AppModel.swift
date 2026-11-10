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
                userDirectory: support.appendingPathComponent("recipes", isDirectory: true)
            ),
            hub: hub,
            downloads: DownloadManager(
                storage: storage,
                downloader: FileDownloader { url in HFClient.authorizationHeader(for: url, token: tokenStore.read()) }
            )
        )
        let gallery = GalleryLibrary(store: GalleryStore(directory: GalleryStore.defaultDirectory))
        let generation = GenerationStore(
            library: library,
            gallery: gallery,
            engine: StableDiffusionCppEngine(
                helperURL: Bundle.main.url(forAuxiliaryExecutable: "kiln-engine")
                    ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/kiln-engine"),
                storage: storage
            )
        )

        self.library = library
        self.gallery = gallery
        self.generation = generation
        account = HubAccount(tokenStore: tokenStore, hub: hub)

        library.onInstalledChange = { [weak generation] in
            generation?.selectDefaultRecipeIfNeeded()
        }
    }

    // MARK: - Actions across features

    /// Opens Generate with an empty canvas.
    func newImage() {
        generation.startOver()
        selection = .generate
    }

    /// Opens a past image on the Generate canvas.
    func show(_ item: GalleryItem) {
        generation.show(item)
        selection = .generate
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

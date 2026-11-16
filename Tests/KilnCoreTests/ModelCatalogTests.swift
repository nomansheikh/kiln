import Foundation
import Testing
@testable import KilnCore

/// The questions the app asks about its models.
@Suite struct ModelCatalogTests {
    private let speech = SpeechDraftFixture()
    private let image = makeRecipe(id: "sdxl", components: [
        .init(role: .checkpoint, repo: "stabilityai/sdxl", file: "sd_xl_base.safetensors", sizeBytes: 6_000_000_000),
    ])
    /// One part of a model, downloaded by itself from the Hugging Face list.
    private let lonePart = makeRecipe(id: "part", components: [
        .init(role: .checkpoint, repo: "someone/parts", file: "text_encoder.safetensors", sizeBytes: 5_000_000_000),
    ])

    private func status(_ state: DownloadStatus.State) -> DownloadStatus {
        DownloadStatus(state: state, receivedBytes: 10, totalBytes: 100, currentFile: nil)
    }

    private func catalog(installed: Set<String> = [], statuses: [String: DownloadStatus] = [:]) -> ModelCatalog {
        ModelCatalog(
            recipes: [speech.named, image, lonePart, speech.styled], userRecipeIDs: ["part"], catalogIDs: ["styled"],
            installedIDs: installed, downloadStatuses: statuses
        )
    }

    // MARK: - Installed models

    @Test func onlyInstalledModelsThatAreWholeCanBeUsed() {
        let catalog = catalog(installed: ["named", "part"])
        #expect(catalog.installedRecipes.map(\.id) == ["named"])
        #expect(catalog.isInstalled(lonePart))
        #expect(!catalog.isInstalled(image))
    }

    @Test func theGenerateScreenStartsWithAnImageModelIfThereIsOne() {
        #expect(catalog(installed: ["named", "sdxl"]).defaultRecipe?.id == "sdxl")
        #expect(catalog(installed: ["named"]).defaultRecipe?.id == "named")
        #expect(catalog().defaultRecipe == nil)
    }

    // MARK: - Downloads

    @Test func activeDownloadsAreThoseStillMoving() {
        let catalog = catalog(statuses: [
            "named": status(.downloading), "sdxl": status(.paused), "part": status(.queued), "styled": status(.completed),
        ])
        #expect(catalog.activeDownloads.map(\.recipe.id) == ["named", "part"])
    }

    @Test func theDownloadsListShowsEveryStatusWithTheActiveOnesFirst() {
        let catalog = catalog(statuses: [
            "named": status(.failed("No space.")), "sdxl": status(.verifying), "styled": status(.completed), "gone": status(.queued),
        ])
        let entries = catalog.downloadEntries
        #expect(entries.first?.recipe.id == "sdxl")
        // A status for a recipe that no longer exists is not shown.
        #expect(Set(entries.map(\.recipe.id)) == ["named", "sdxl", "styled"])
    }

    // MARK: - The Models list

    @Test func theListCanBeNarrowedToATaskAndToDownloadedModels() {
        let catalog = catalog(installed: ["named", "sdxl"])
        #expect(catalog.listed().count == 4)
        #expect(catalog.listed(task: .textToSpeech).map(\.id) == ["named", "styled"])
        #expect(catalog.listed(task: .textToSpeech, downloadedOnly: true).map(\.id) == ["named"])
        #expect(catalog.listed(task: .speechToText).isEmpty)
    }

    @Test func aSearchMatchesTheNameTheIdOrARepoWhateverTheCase() {
        let catalog = catalog()
        #expect(catalog.listed(query: "SDXL").map(\.id) == ["sdxl"])
        #expect(catalog.listed(query: "test").map(\.id) == ["sdxl", "part"])
        #expect(catalog.listed(query: "stabilityai").map(\.id) == ["sdxl"])
        #expect(catalog.listed(query: "nothing like this").isEmpty)
    }

    @Test func aPastedLinkMatchesTheRepoItNames() {
        #expect(catalog().listed(query: "https://huggingface.co/someone/parts/tree/main").map(\.id) == ["part"])
    }

    @Test func aRepoOnlyAnotherVariantUsesIsFoundToo() {
        let other = makeRecipe(components: [.init(role: .checkpoint, repo: "elsewhere/quantized", file: "q4.gguf")])
        let found = catalog().listed(query: "elsewhere") { $0.id == "sdxl" ? [other] : [] }
        #expect(found.map(\.id) == ["sdxl"])
    }

    // MARK: - Hugging Face repos

    @Test func aRepoOfACuratedRecipeIsAnsweredWithThatRecipe() {
        #expect(catalog().curatedRecipe(forRepo: "stabilityai/sdxl")?.id == "sdxl")
        // Recipes the user added and catalogue entries do not count as curated.
        #expect(catalog().curatedRecipe(forRepo: "someone/parts") == nil)
        #expect(catalog().curatedRecipe(forRepo: "unknown/repo") == nil)
        #expect(catalog().support(forRepo: "stabilityai/sdxl", info: nil, failed: true, usableBytes: 0) == .recipe(image))
    }

    @Test func aRepoWhoseFilesAreNotKnownYetIsCheckingOrUnavailable() {
        #expect(catalog().support(forRepo: "new/repo", info: nil, failed: false, usableBytes: 0) == .checking)
        #expect(catalog().support(forRepo: "new/repo", info: nil, failed: true, usableBytes: 0) == .unavailable)
    }

    @Test func aRepoOfAKnownModelOffersItsBestFileWithThatRecipe() throws {
        let base = RecipeFamilyTests.baseRecipe()
        let catalog = ModelCatalog(recipes: [base])
        let info = try RecipeFamilyTests.info()
        let usable = Double(16 * RecipeFamilyTests.gib)

        guard case .family(let file, _, let recipe) = catalog.support(forRepo: info.id, info: info, failed: false, usableBytes: usable) else {
            Issue.record("expected the repo to be offered with the recipe of its model")
            return
        }
        #expect(file.path == "z-image-turbo-Q8_0.gguf")
        #expect(recipe == base)
        #expect(catalog.familyRecipe(for: info) == base)
        // The same recipe added by the user is not a base to build on.
        #expect(ModelCatalog(recipes: [base], userRecipeIDs: [base.id]).familyRecipe(for: info) == nil)
    }

    @Test func aRepoWithAWholeModelInOneFileOffersIt() throws {
        let info = try RecipeFamilyTests.info(tags: [], files: [("model.safetensors", 6 * RecipeFamilyTests.gib), ("vae.safetensors", 300)])
        let support = catalog().support(forRepo: info.id, info: info, failed: false, usableBytes: Double(16 * RecipeFamilyTests.gib))
        guard case .checkpoint(let file, _) = support else {
            Issue.record("expected a one-file model")
            return
        }
        #expect(file.path == "model.safetensors")
    }

    @Test func aRepoInSeveralPartsWithoutARecipeIsUnsupported() throws {
        let info = try RecipeFamilyTests.info(tags: [], files: [("unet/model.safetensors", 6 * RecipeFamilyTests.gib)])
        #expect(catalog().support(forRepo: info.id, info: info, failed: false, usableBytes: 1e12) == .unsupported)
    }

    @Test func aFileIsJudgedByTheRecipeMadeForIt() throws {
        let info = try RecipeFamilyTests.info()
        let file = try #require(info.files.first)
        let made = makeRecipe(id: "made", components: [.init(role: .diffusionModel, repo: info.id, file: file.path)])

        #expect(ModelCatalog().availability(of: file, in: info) == .available)
        #expect(ModelCatalog(recipes: [made]).recipe(for: file, in: info) == made)
        #expect(ModelCatalog(recipes: [made], installedIDs: ["made"]).availability(of: file, in: info) == .installed)
        let moving = ModelCatalog(recipes: [made], downloadStatuses: ["made": status(.downloading)])
        #expect(moving.availability(of: file, in: info) == .transferring(status(.downloading)))
        let paused = ModelCatalog(recipes: [made], downloadStatuses: ["made": status(.paused)])
        #expect(paused.availability(of: file, in: info) == .available)
    }
}

import Foundation
import Testing
@testable import KilnCore

@Suite struct VariantSelectionTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-variant-tests-\(UUID().uuidString)")
    private let suite = "kiln-variant-tests-\(UUID().uuidString)"
    private let gigabyte: Int64 = 1_073_741_824

    /// A model in a large and a small version, on a Mac that fits only the small one.
    private var recipe: ModelRecipe {
        makeRecipe(components: [.init(role: .vae, repo: "o/r", file: "vae.safetensors", sizeBytes: 1_000)]).with(variants: [
            .init(id: "q8", name: "Q8", components: [.init(role: .diffusionModel, repo: "o/r", file: "q8.gguf", sizeBytes: 12 * gigabyte)]),
            .init(id: "q4", name: "Q4", components: [.init(role: .diffusionModel, repo: "o/r", file: "q4.gguf", sizeBytes: 4 * gigabyte)]),
        ])
    }

    private func selection() throws -> VariantSelection {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return VariantSelection(
            storage: ModelStorage(root: root),
            memory: MemoryFitEstimator(physicalMemoryBytes: UInt64(16 * gigabyte)),
            defaults: defaults
        )
    }

    private func install(_ variantID: String, with selection: VariantSelection) throws {
        let variant = try #require(recipe.resolvedVariants.first { $0.selectedVariantID == variantID })
        for component in variant.components {
            let file = selection.storage.url(for: component)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("weights".utf8).write(to: file)
        }
    }

    @Test func aRecipeWithoutVariantsIsReturnedAsItIs() throws {
        let plain = makeRecipe()
        #expect(try selection().resolve(plain) == plain)
    }

    @Test func theBestFitForTheMacIsOfferedFirst() throws {
        let resolved = try selection().resolve(recipe)
        #expect(resolved.selectedVariantID == "q4")
        #expect(resolved.components.map(\.file) == ["vae.safetensors", "q4.gguf"])
    }

    @Test func aVariantAlreadyOnDiskWinsOverTheBestFit() throws {
        let selection = try selection()
        try install("q8", with: selection)
        #expect(selection.resolve(recipe).selectedVariantID == "q8")
    }

    @Test func theUsersChoiceWinsOverBothAndIsRemembered() throws {
        let selection = try selection()
        try install("q4", with: selection)
        selection.choose("q8", for: recipe.id)

        #expect(selection.resolve(recipe).selectedVariantID == "q8")
        // A second instance reads the same choice, as after a relaunch.
        #expect(try self.selection().resolve(recipe).selectedVariantID == "q8")
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func aChoiceTheRecipeNoLongerHasIsIgnored() throws {
        let selection = try selection()
        selection.choose("q2", for: recipe.id)
        #expect(selection.resolve(recipe).selectedVariantID == "q4")
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

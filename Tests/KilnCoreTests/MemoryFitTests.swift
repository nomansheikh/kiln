import Foundation
import Testing
@testable import KilnCore

@Suite struct MemoryFitTests {
    private func estimator(gb: Double) -> MemoryFitEstimator {
        MemoryFitEstimator(physicalMemoryBytes: UInt64(gb * 1_073_741_824))
    }

    private func recipe(sizeGB: Double?, minMemoryGB: Double? = nil) -> ModelRecipe {
        makeRecipe(
            components: [.init(role: .checkpoint, repo: "a/b", file: "f.gguf", sizeBytes: sizeGB.map { Int64($0 * 1_073_741_824) })],
            minMemoryGB: minMemoryGB
        )
    }

    @Test func usableMemoryLeavesRoomForTheSystem() {
        // 16 GB - 2.5 GB reserve - 10% = 11.9 GB
        #expect(abs(estimator(gb: 16).usableBytes / 1_073_741_824 - 11.9) < 0.001)
        #expect(estimator(gb: 1).usableBytes == 0)
    }

    @Test func classifiesBySizeAgainstUsableMemory() {
        let mac = estimator(gb: 16) // usable 11.9 GB, comfortable up to 10.115 GB

        #expect(mac.fit(for: recipe(sizeGB: 6)) == .comfortable)
        #expect(mac.fit(for: recipe(sizeGB: 10.1)) == .comfortable)
        #expect(mac.fit(for: recipe(sizeGB: 11)) == .tight)
        #expect(mac.fit(for: recipe(sizeGB: 12)) == .tooLarge)
    }

    @Test func declaredMinimumOverridesASmallFileSize() {
        #expect(estimator(gb: 16).fit(for: recipe(sizeGB: 1, minMemoryGB: 24)) == .tooLarge)
        #expect(estimator(gb: 24).fit(for: recipe(sizeGB: 1, minMemoryGB: 24)) == .comfortable)
    }

    @Test func unknownSizeFallsBackToTheDeclaredMinimum() {
        #expect(estimator(gb: 32).fit(for: recipe(sizeGB: nil, minMemoryGB: 16)) == .comfortable)
        #expect(estimator(gb: 8).fit(for: recipe(sizeGB: nil, minMemoryGB: 16)) == .tooLarge)
        #expect(estimator(gb: 32).fit(for: recipe(sizeGB: nil)) == nil)
    }

    @Test func curatedQwenRecipeMatchesItsDeclaredMinimum() throws {
        let file = curatedRecipesDirectory.appendingPathComponent("qwen-image-2.1-turbo.json")
        let qwen = try RecipeStore.decode(Data(contentsOf: file))

        #expect(estimator(gb: 16).fit(for: qwen) == .tooLarge)
        #expect(estimator(gb: 24).fit(for: qwen) == .comfortable)
        #expect(estimator(gb: 64).fit(for: qwen) == .comfortable)
    }
}

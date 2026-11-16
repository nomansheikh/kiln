import Foundation
import Testing
@testable import KilnCore

/// Small facts the Models and Settings screens show about a model and its files.
@Suite struct ModelDetailsTests {
    @Test func aRecipesSourcesAreListedOnceInOrder() {
        let recipe = makeRecipe(components: [
            .init(role: .diffusionModel, repo: "leejet/model", file: "a.gguf"),
            .init(role: .vae, repo: "Comfy-Org/parts", file: "vae.safetensors"),
            .init(role: .llm, repo: "leejet/encoder", file: "b.gguf"),
            .init(role: .clipL, repo: "Comfy-Org/parts", file: "clip.safetensors"),
        ])
        #expect(recipe.sourceRepos == ["leejet/model", "Comfy-Org/parts", "leejet/encoder"])
        #expect(recipe.sourceOwners == ["leejet", "Comfy-Org"])
        #expect(recipe.fileCountText == "4 files")
        #expect(makeRecipe().fileCountText == "1 file")
    }

    @Test func aSingleFileIsJudgedAgainstTheMemoryAModelCanUse() {
        let memory = MemoryFitEstimator(physicalMemoryBytes: 16 * 1_073_741_824)
        let usable = memory.usableBytes
        #expect(memory.fit(forFileOfSize: Int64(usable * 0.5)) == .comfortable)
        #expect(memory.fit(forFileOfSize: Int64(usable * 0.9)) == .tight)
        #expect(memory.fit(forFileOfSize: Int64(usable * 1.1)) == .tooLarge)
    }

    @Test func aTransferIsDescribedByWhatIsKnownAboutIt() {
        let unknown = DownloadStatus(state: .downloading, receivedBytes: 1_000_000, totalBytes: nil, currentFile: nil)
        #expect(unknown.percentText == nil)
        #expect(!unknown.transferCaption.contains(" of "))
        #expect(!unknown.transferCaption.contains("·"))

        let known = DownloadStatus(state: .downloading, receivedBytes: 250, totalBytes: 1_000, currentFile: "split_files/vae/ae.safetensors")
        #expect(known.percentText?.contains("25") == true)
        let parts = known.transferCaption.components(separatedBy: " · ")
        #expect(parts.count == 3)
        #expect(parts[0].contains(" of "))
        #expect(parts[2] == "ae.safetensors")
    }

    @Test func aFoldersSizeCountsItsFilesAtAnyDepth() throws {
        let files = try FileFixtures()
        #expect(DirectorySize.bytes(in: files.root) == 0)
        #expect(DirectorySize.bytes(in: files.root.appendingPathComponent("missing")) == 0)

        let nested = files.root.appendingPathComponent("a/b")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: nested.appendingPathComponent("weights.bin"))
        try Data(count: 50_000).write(to: files.root.appendingPathComponent("top.bin"))

        // Allocated size is rounded up to whole blocks, so it is at least the bytes written.
        let size = DirectorySize.bytes(in: files.root)
        #expect(size >= 150_000 && size < 400_000)
    }
}

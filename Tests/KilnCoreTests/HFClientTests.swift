import Foundation
import Testing
@testable import KilnCore

@Suite struct HFClientTests {
    // Trimmed from real api/models responses.
    static let searchBody = """
    [
      {"_id": "1", "id": "Comfy-Org/Qwen-Image-2.1", "likes": 1303, "private": false, "downloads": 10186265,
       "tags": ["diffusion-single-file", "text-to-image", "license:other", "region:us"],
       "pipeline_tag": "text-to-image", "modelId": "Comfy-Org/Qwen-Image-2.1"},
      {"_id": "2", "id": "unsloth/Qwen-Image-2.1-GGUF", "likes": 465, "private": false, "downloads": 1620476,
       "tags": ["gguf", "text-to-image", "license:apache-2.0"], "pipeline_tag": "text-to-image"}
    ]
    """

    static let infoBody = """
    {"id": "AtomicChat/Qwen-Image-2.1-Turbo-GGUF", "sha": "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4",
     "gated": false, "tags": ["gguf", "license:other"],
     "siblings": [
       {"rfilename": ".gitattributes", "blobId": "1b", "size": 2447},
       {"rfilename": "Qwen-Image-2.1-Turbo-AD-Q2_K.gguf", "blobId": "01", "size": 2553333472,
        "lfs": {"sha256": "8ab2888f605030a894c6238d978f51427bfde6732f4a112c71cff0439e265d04", "size": 2553333472, "pointerSize": 135}},
       {"rfilename": "Qwen-Image-2.1-Turbo-Q8_0.gguf", "blobId": "02", "size": 7591577312,
        "lfs": {"sha256": "8d74ae0be534df394ea2d29f04b77f879318c9e0df20a3e208e6bedbf89b4159", "size": 7591577312, "pointerSize": 135}},
       {"rfilename": "README.md", "blobId": "03", "size": 9000}
     ]}
    """

    @Test func searchSendsTextToImageFilterAndDecodesResults() async throws {
        let transport = MockTransport(body: Self.searchBody)
        let client = HFClient(transport: transport)

        let results = try await client.searchModels(query: " qwen image ", limit: 5)

        let url = try #require(transport.requests.first?.url)
        let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(url.path == "/api/models")
        #expect(query == ["pipeline_tag": "text-to-image", "sort": "downloads", "direction": "-1", "limit": "5", "search": "qwen image"])

        #expect(results.map(\.id) == ["Comfy-Org/Qwen-Image-2.1", "unsloth/Qwen-Image-2.1-GGUF"])
        #expect(results[0].downloads == 10_186_265)
        #expect(results[0].author == "Comfy-Org")
        #expect(results[1].license == "apache-2.0")
    }

    @Test func emptyQueryOmitsTheSearchParameter() async throws {
        let transport = MockTransport(body: "[]")
        _ = try await HFClient(transport: transport).searchModels(query: "  ")

        let url = try #require(transport.requests.first?.url)
        #expect(!url.absoluteString.contains("search="))
    }

    @Test func modelInfoListsFilesWithSizeAndChecksum() async throws {
        let transport = MockTransport(body: Self.infoBody)
        let info = try await HFClient(transport: transport).modelInfo(repo: "AtomicChat/Qwen-Image-2.1-Turbo-GGUF")

        #expect(transport.requests.first?.url?.absoluteString
            == "https://huggingface.co/api/models/AtomicChat/Qwen-Image-2.1-Turbo-GGUF?blobs=true")
        #expect(info.revision == "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4")
        #expect(!info.isGated)
        #expect(info.license == "other")
        #expect(info.weightFiles.map(\.name) == ["Qwen-Image-2.1-Turbo-Q8_0.gguf", "Qwen-Image-2.1-Turbo-AD-Q2_K.gguf"])
        #expect(info.weightFiles[0].sizeBytes == 7_591_577_312)
        #expect(info.weightFiles[0].sha256 == "8d74ae0be534df394ea2d29f04b77f879318c9e0df20a3e208e6bedbf89b4159")
    }

    @Test(arguments: [#""auto""#, #""manual""#, "true"])
    func gatedReposAreDetected(gated: String) async throws {
        let transport = MockTransport(body: #"{"id": "a/b", "gated": \#(gated)}"#)
        let info = try await HFClient(transport: transport).modelInfo(repo: "a/b")
        #expect(info.isGated)
        #expect(info.files.isEmpty)
    }

    @Test func tokenIsSentToHuggingFaceOnly() async throws {
        let transport = MockTransport(body: "[]")
        _ = try await HFClient(transport: transport, token: { "hf_secret" }).searchModels(query: "")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer hf_secret")

        let cdn = URL(string: "https://cdn-lfs.example.com/file")!
        let plainHTTP = URL(string: "http://huggingface.co/a/b")!
        let lookalike = URL(string: "https://huggingface.co.evil.example/a")!
        #expect(HFClient.authorizationHeader(for: cdn, token: "hf_secret") == nil)
        #expect(HFClient.authorizationHeader(for: plainHTTP, token: "hf_secret") == nil)
        #expect(HFClient.authorizationHeader(for: lookalike, token: "hf_secret") == nil)
        #expect(HFClient.authorizationHeader(for: URL(string: "https://huggingface.co/a")!, token: "") == nil)
    }

    @Test func noTokenMeansNoAuthorizationHeader() async throws {
        let transport = MockTransport(body: "[]")
        _ = try await HFClient(transport: transport).searchModels(query: "")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func mapsHTTPStatusesToErrors() async {
        func error(status: Int, token: String? = nil) async -> HFError? {
            let client = HFClient(transport: MockTransport(status: status, body: "{}"), token: { token })
            do {
                _ = try await client.modelInfo(repo: "a/b")
                return nil
            } catch {
                return error as? HFError
            }
        }

        #expect(await error(status: 401) == .accessDenied(repo: "a/b"))
        #expect(await error(status: 401, token: "hf_bad") == .unauthorized)
        #expect(await error(status: 403, token: "hf_ok") == .accessDenied(repo: "a/b"))
        #expect(await error(status: 404) == .notFound)
        #expect(await error(status: 429) == .rateLimited)
        #expect(await error(status: 503) == .http(status: 503))
    }

    @Test func malformedBodyIsAnInvalidResponse() async {
        let client = HFClient(transport: MockTransport(body: "<html>"))
        await #expect(throws: HFError.invalidResponse) { try await client.searchModels(query: "") }
    }

    @Test func buildsPinnedDownloadURLs() {
        let pinned = HFClient.downloadURL(repo: "Comfy-Org/Qwen-Image-2.1", file: "vae/v.safetensors", revision: "abc123")
        #expect(pinned.absoluteString == "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/abc123/vae/v.safetensors")

        let floating = HFClient.downloadURL(repo: "a/b", file: "m.gguf", revision: nil)
        #expect(floating.absoluteString == "https://huggingface.co/a/b/resolve/main/m.gguf")
    }

    @Test(arguments: [
        ("Qwen-Image-2.1-Turbo-Q8_0.gguf", "Q8_0"),
        ("Qwen-Image-2.1-Turbo-AD-Q4_K.gguf", "Q4_K"),
        ("Qwen3VL-8B-Instruct-Q4_K_M.gguf", "Q4_K_M"),
        ("Qwen-Image-2.1-Turbo-BF16.gguf", "BF16"),
        ("vae/qwen_image_2.1_vae_bf16.safetensors", "BF16"),
        ("model-IQ4_XS.gguf", "IQ4_XS"),
        ("diffusion_models/qwen_image_2.1_int8_convrot.safetensors", "INT8"),
    ])
    func parsesQuantization(path: String, expected: String) {
        #expect(HFFile(path: path, sizeBytes: nil, sha256: nil).quantization == expected)
    }

    @Test func aHubFileBecomesAValidPinnedSingleFileRecipe() async throws {
        let info = try await HFClient(transport: MockTransport(body: Self.infoBody))
            .modelInfo(repo: "AtomicChat/Qwen-Image-2.1-Turbo-GGUF")
        let file = try #require(info.weightFiles.first)

        let recipe = ModelRecipe.singleFile(file, in: info)

        try recipe.validate()
        #expect(recipe.id == "atomicchat-qwen-image-2.1-turbo-gguf-qwen-image-2.1-turbo-q8-0.gguf")
        #expect(recipe.engine == "sd.cpp")
        #expect(recipe.components == [
            .init(role: .checkpoint, repo: "AtomicChat/Qwen-Image-2.1-Turbo-GGUF", file: "Qwen-Image-2.1-Turbo-Q8_0.gguf",
                  revision: "cbcb9ff83b17e1eeef693479a8d34cea355a0ee4", sizeBytes: 7_591_577_312,
                  sha256: "8d74ae0be534df394ea2d29f04b77f879318c9e0df20a3e208e6bedbf89b4159"),
        ])
        #expect(recipe.defaults.width == 512)
        #expect(ModelRecipe.singleFile(HFFile(path: "sd_xl_base_1.0.safetensors", sizeBytes: 1, sha256: nil), in: info).defaults.width == 1024)
    }

    @Test func savedRecipesLoadBackFromTheUserDirectory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-tests-\(UUID().uuidString)")
        let store = RecipeStore(bundledDirectory: root.appendingPathComponent("bundled"), userDirectory: root.appendingPathComponent("user"))
        let recipe = makeRecipe(id: "from-hub")

        try store.save(recipe)

        #expect(store.loadAll().recipes == [recipe])
    }

    @Test(arguments: [
        ("sd_xl_base_1.0.safetensors", 6_938_078_334, true),
        ("v1-5-pruned-emaonly.safetensors", 4_265_146_304, true),
        ("Qwen3VL-8B-Instruct-Q8_0.gguf", 8_709_519_456, false), // GGUF is published per part
        ("vae/qwen_image_2.1_vae_bf16.safetensors", 675_509_688, false), // in a subfolder
        ("text_encoders/qwen3vl_8b_bf16.safetensors", 17_530_000_000, false),
        ("sdxl_vae.safetensors", 2_000_000_000, false), // named as a part
        ("sd_xl_offset_example-lora_1.0.safetensors", 49_553_604, false), // too small and a LoRA
    ])
    func guessesWhichFilesAreWholeModels(path: String, size: Int64, expected: Bool) {
        #expect(HFFile(path: path, sizeBytes: size, sha256: nil).looksLikeStandaloneCheckpoint == expected)
    }

    @Test func aLoneTextEncoderIsAnIncompleteRecipe() async throws {
        let info = try await HFClient(transport: MockTransport(body: Self.infoBody))
            .modelInfo(repo: "AtomicChat/Qwen-Image-2.1-Turbo-GGUF")
        let encoder = ModelRecipe.singleFile(try #require(info.weightFiles.first), in: info)
        let checkpoint = ModelRecipe.singleFile(HFFile(path: "sd_xl_base_1.0.safetensors", sizeBytes: 6_938_078_334, sha256: nil), in: info)

        #expect(encoder.isIncompleteSingleFile)
        #expect(!checkpoint.isIncompleteSingleFile)
        // A multi-part recipe is never judged this way, whatever its files are called.
        #expect(!makeRecipe(components: [
            .init(role: .llm, repo: "a/b", file: "enc.gguf"), .init(role: .vae, repo: "a/b", file: "vae.safetensors"),
        ]).isIncompleteSingleFile)
    }

    @Test func userRecipesAreTrackedAndCanBeRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-tests-\(UUID().uuidString)")
        let store = RecipeStore(bundledDirectory: root.appendingPathComponent("bundled"), userDirectory: root.appendingPathComponent("user"))
        try FileManager.default.createDirectory(at: store.bundledDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(makeRecipe(id: "bundled")).write(to: store.bundledDirectory.appendingPathComponent("bundled.json"))
        try store.save(makeRecipe(id: "mine"))

        #expect(store.loadAll().userRecipeIDs == ["mine"])

        try store.removeUserRecipe(id: "mine")
        try store.removeUserRecipe(id: "bundled") // only looks in the user folder

        #expect(store.loadAll().recipes.map(\.id) == ["bundled"])
    }

    @Test func filesWithoutAQuantLabelHaveNone() {
        #expect(HFFile(path: "sd_xl_base_1.0.safetensors", sizeBytes: nil, sha256: nil).quantization == nil)
        #expect(HFFile(path: "mmproj-model-F16.gguf", sizeBytes: nil, sha256: nil).isVisionProjector)
    }
}

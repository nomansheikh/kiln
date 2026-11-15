import Foundation
import Testing
@testable import KilnCore

/// Searching Hugging Face by a repo's id or by a link to it.
@Suite struct HFRepoSearchTests {
    private static let search = "https://huggingface.co/api/models?pipeline_tag=text-to-image&sort=downloads&direction=-1&limit=30&search="

    @Test func aRepoIDFindsThatRepoFirstWhateverItHolds() async throws {
        let transport = RoutedTransport()
        transport.route("https://huggingface.co/api/models/ggerganov/whisper.cpp", body: """
        {"id": "ggerganov/whisper.cpp", "likes": 900, "downloads": 5000, "tags": ["automatic-speech-recognition", "license:mit"]}
        """)
        transport.route(Self.search + "ggerganov/whisper.cpp", body: HFClientTests.searchBody)
        let client = HFClient(transport: transport)

        let byID = try await client.searchModels(query: "ggerganov/whisper.cpp")
        let byLink = try await client.searchModels(query: " https://huggingface.co/ggerganov/whisper.cpp/tree/main ")

        #expect(byID.map(\.id) == ["ggerganov/whisper.cpp", "Comfy-Org/Qwen-Image-2.1", "unsloth/Qwen-Image-2.1-GGUF"])
        #expect(byID[0].license == "mit")
        #expect(byLink.map(\.id) == byID.map(\.id))
    }

    @Test func aRepoIDThatDoesNotExistStillSearches() async throws {
        let transport = RoutedTransport()
        transport.route(Self.search + "nobody/nothing", body: "[]")

        #expect(try await HFClient(transport: transport).searchModels(query: "nobody/nothing").isEmpty)
    }

    @Test func theRepoAloneIsEnoughWhenTheWiderSearchFails() async throws {
        let transport = RoutedTransport()
        transport.route("https://huggingface.co/api/models/owner/name", body: #"{"id": "owner/name"}"#)
        transport.route(Self.search + "owner/name", status: 500, body: "")

        #expect(try await HFClient(transport: transport).searchModels(query: "owner/name").map(\.id) == ["owner/name"])
    }

    @Test func onlyAnOwnerAndNameCountAsARepoID() {
        #expect(HFClient.repoID(in: "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice") == "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice")
        #expect(HFClient.repoID(in: "huggingface.co/audio-cpp/audio.cpp-gguf/blob/main/README.md") == "audio-cpp/audio.cpp-gguf")
        #expect(HFClient.repoID(in: "qwen image") == nil)
        #expect(HFClient.repoID(in: "flux") == nil)
        #expect(HFClient.repoID(in: "a/") == nil)
        #expect(HFClient.repoID(in: "../secret") == nil)
        #expect(HFClient.repoID(in: "owner/na me") == nil)
    }
}

import Foundation
import Testing
@testable import KilnCore

/// Every error the user can be shown is a sentence in plain language: it says
/// what happened, names what it is about, and gives no type names or jargon.
/// Reasons passed in from the system are given here as the system writes them.
@Suite struct ErrorMessageTests {
    private static let engine: [EngineError] = [
        .busy, .unsupportedEngine("llama.cpp"), .missingComponents(["vae.safetensors", "llm.gguf"]), .unreadableSourceImage,
        .missingAudio, .missingText, .missingInstruction, .missingReference, .missingReferenceText, .unreadableReference,
        .tooManySpeakers(4), .missingSpeakerVoice("Anna"), .scriptStopped(finished: 2, total: 5, detail: "out of memory"),
        .unknownVoice("zed"), .unreadableAudio, .helperUnavailable("The file is missing."), .modelLoadFailed(detail: "bad file"),
        .outOfMemory, .crashed(detail: "signal 9"), .generationFailed(detail: "nan"), .invalidOutput,
    ]
    private static let hub: [HFError] = [
        .unauthorized, .accessDenied(repo: "owner/name"), .accessDenied(repo: nil), .notFound, .rateLimited, .http(status: 500),
        .invalidResponse,
    ]
    private static let downloads: [DownloadError] = [
        .accessDenied, .http(status: 503), .network("The connection was lost."), .sizeMismatch(expected: 10, actual: 4),
        .checksumMismatch, .noChecksum(file: "vocab.json"), .notEnoughDiskSpace(needed: 5_000_000_000, available: 1_000_000_000),
    ]
    private static let recipes: [RecipeValidationError] = [
        .invalidID("Bad Id"), .emptyName, .noComponents, .duplicateRole(.vae), .invalidRepo("nope"), .unsafeFilePath("../x"),
        .invalidSHA256(file: "a.gguf"), .invalidSize(file: "a.gguf"), .invalidDefaults("steps must be greater than zero"),
        .missingDefaults, .invalidSpeech("no family"), .invalidLanguages, .invalidVariant("Q 8"),
    ]
    private static let others: [any LocalizedError] = [
        VoiceError.missingName, ReleaseCheckError.http(status: 502), ReleaseCheckError.unreadableResponse,
        RecipeStore.ImportError.idTaken("sdxl"), AttachmentLibrary.ImportError.notAccepted([.audio]), KeychainError(status: -25300),
    ]

    static let all: [any LocalizedError] = engine + hub + downloads + recipes + others

    @Test(arguments: all.indices)
    func everyErrorIsAPlainSentence(_ index: Int) throws {
        let error = Self.all[index]
        let text = try #require(error.errorDescription, "\(error) has no message")
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""

        #expect(firstLine.first?.isUppercase == true || firstLine.first == "\"", "\(text)")
        #expect(firstLine.last.map { ".:!?".contains($0) } == true || text.contains("\n"), "\(text)")
        for jargon in ["Error", "Optional(", "nil", "KilnCore", "Swift.", "errSec", "(rawValue"] {
            #expect(!text.contains(jargon), "\(text)")
        }
    }

    @Test func anErrorNamesWhatItIsAbout() {
        #expect(EngineError.missingComponents(["a.gguf", "b.gguf"]).errorDescription?.contains("a.gguf, b.gguf") == true)
        #expect(EngineError.missingSpeakerVoice("Anna").errorDescription?.hasPrefix("Anna ") == true)
        #expect(EngineError.unknownVoice("zed").errorDescription?.contains("\"zed\"") == true)
        #expect(EngineError.tooManySpeakers(4).errorDescription?.contains("4 voices") == true)
        #expect(HFError.accessDenied(repo: "owner/name").errorDescription?.contains("owner/name") == true)
        #expect(HFError.http(status: 500).errorDescription?.contains("500") == true)
        #expect(DownloadError.noChecksum(file: "vocab.json").errorDescription?.contains("vocab.json") == true)
        #expect(RecipeValidationError.duplicateRole(.vae).errorDescription?.contains("\"vae\"") == true)
        #expect(RecipeStore.ImportError.idTaken("sdxl").errorDescription?.contains("\"sdxl\"") == true)
    }

    @Test func anEngineFailureCarriesTheEnginesOwnWordsOnASecondLine() {
        #expect(EngineError.crashed(detail: "").errorDescription == "The engine stopped unexpectedly.")
        #expect(EngineError.crashed(detail: "signal 9").errorDescription == "The engine stopped unexpectedly.\nsignal 9")
        let stopped = EngineError.scriptStopped(finished: 2, total: 5, detail: "out of memory").errorDescription
        #expect(stopped?.hasPrefix("Only the first 2 of 5 lines were read") == true)
        #expect(stopped?.contains("Line 3 could not be read.") == true)
        #expect(stopped?.hasSuffix("\nout of memory") == true)
    }

    @Test func progressIsAFractionOnlyWhenTheTotalIsKnown() {
        #expect(GenerationProgress(stage: .sampling, completed: 2, total: 8).fraction == 0.25)
        #expect(GenerationProgress(stage: .sampling, completed: 9, total: 8).fraction == 1)
        #expect(GenerationProgress(stage: .speaking, completed: 0, total: 0).fraction == nil)
    }

    @Test func editStrengthsAreNamedInPlainWords() {
        #expect(EditStrength.allCases.map(\.rawValue) == [0.35, 0.6, 0.8])
        #expect(EditStrength.allCases.map(\.title) == ["Subtle", "Balanced", "Strong"])
        #expect(Set(EditStrength.allCases.map(\.explanation)).count == 3)
        #expect(EditStrength.balanced.id == 0.6)
    }
}

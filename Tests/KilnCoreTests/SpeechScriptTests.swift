import Foundation
import Testing
@testable import KilnCore

@Suite struct SpeechScriptTests {
    @Test func readsNamedTurnsInOrder() {
        let script = SpeechScript("Anna: Did you hear that?\nBen: Hear what?\nanna: The window.")
        #expect(script.speakers == ["Anna", "Ben"])
        #expect(script.turns.map(\.speaker) == ["Anna", "Ben", "Anna"])
        #expect(script.turns.map(\.text) == ["Did you hear that?", "Hear what?", "The window."])
    }

    @Test func textWithoutNamesHasOneSpeaker() {
        let script = SpeechScript("Just a sentence.\nAnd another line.")
        #expect(script.speakers == [SpeechScript.unnamedSpeaker])
        #expect(script.turns.map(\.text) == ["Just a sentence. And another line."])
        #expect(script.turns.first?.label == nil)
    }

    @Test func linesWithoutANameBelongToTheTurnBefore() {
        let script = SpeechScript("Once upon a time.\nSpeaker 1: Hello\nthere.\n\nSpeaker 2: Hi.")
        #expect(script.speakers == ["Speaker 1", "Speaker 2"])
        #expect(script.turns.map(\.text) == ["Once upon a time.", "Hello there.", "Hi."])
    }

    @Test func timesLinksAndSentencesAreNotNames() {
        for text in ["10:30 is the time.", "https://example.com is a site.", "He said, loudly: go away.",
                     "This sentence is far too long to be a name: so it is text.", "[laughs]: no."] {
            #expect(SpeechScript(text).turns.first?.label == nil, "\(text)")
        }
    }

    @Test func labelRangesCoverTheNameAndColon() {
        let text = "Anna: Hi.\n  Ben : Yo."
        let ranges = SpeechScript(text).turns.compactMap(\.label).map { (text as NSString).substring(with: $0) }
        #expect(ranges == ["Anna:", "  Ben :"])
    }

    @Test func aNoteInBracketsAfterTheNameSaysHowTheTurnIsSaid() {
        let script = SpeechScript("Anna (whispering): Did you hear that?\nBen: No.\nAnna: Oh.")
        #expect(script.speakers == ["Anna", "Ben"])
        #expect(script.turns.map(\.note) == ["whispering", nil, nil])
        #expect(script.turns.map(\.text) == ["Did you hear that?", "No.", "Oh."])
        #expect(script.rendered(line: "S{n}: {text}") == "S1: Did you hear that?\nS2: No.\nS1: Oh.")
    }

    @Test func oneSpeakerIsNotADialogue() {
        #expect(!SpeechScript("Note: remember the milk.").isDialogue)
        #expect(SpeechScript("An opening line.\nAnna: Hi.").isDialogue)
    }

    @Test func rendersInTheModelsSpellingAndAGivenOrder() {
        let script = SpeechScript("Anna: Hi.\nBen: Yo.\nAnna:\nCleo: Hey.")
        #expect(script.rendered(line: "Speaker {n}: {text}") == "Speaker 1: Hi.\nSpeaker 2: Yo.\nSpeaker 3: Hey.")
        #expect(script.rendered(line: "[S{n}] {text}", order: ["ben", "Cleo", "Anna"]) == "[S3] Hi.\n[S1] Yo.\n[S2] Hey.")
    }

    // MARK: - What the engine is told

    private func recipe(copies: Bool = true) throws -> ModelRecipe {
        var recipe = try VoiceFixture().recipe
        recipe.speech?.reference = copies ? .optional : nil
        recipe.speech?.speakers = .init(max: 2, line: "Speaker {n}: {text}")
        return recipe
    }

    private func voice(_ name: String) -> VoiceReference {
        VoiceReference(file: URL(fileURLWithPath: "/voices/\(name).wav"), name: name)
    }

    @Test func aScriptIsRewrittenForTheModel() throws {
        let direction = try AudioCppEngine.direction(for: GenerationRequest(prompt: "Anna: Hi.\nBen: Yo."), recipe: try recipe())
        #expect(direction.text == "Speaker 1: Hi.\nSpeaker 2: Yo.")
        #expect(direction.samples.isEmpty)
        #expect(direction.voice == nil)
    }

    @Test func speakersWithARecordingAreNumberedFirst() throws {
        let request = GenerationRequest(prompt: "Anna: Hi.\nBen: Yo.", speech: SpeechSettings(cast: ["ben": CastVoice(reference: voice("b"))]))
        let direction = try AudioCppEngine.direction(for: request, recipe: try recipe())
        #expect(direction.text == "Speaker 2: Hi.\nSpeaker 1: Yo.")
        #expect(direction.samples.map(\.lastPathComponent) == ["b.wav"])
        #expect(direction.reference == nil)
    }

    @Test func oneVoiceForTheWholeTextIsTheFirstSpeakers() throws {
        let request = GenerationRequest(prompt: "Hello there.", speech: SpeechSettings(reference: voice("a")))
        let direction = try AudioCppEngine.direction(for: request, recipe: try recipe())
        #expect(direction.text == "Speaker 1: Hello there.")
        #expect(direction.samples.map(\.lastPathComponent) == ["a.wav"])
    }

    @Test func recordingsAreNotSentToAModelThatCannotCopy() throws {
        let request = GenerationRequest(prompt: "Anna: Hi.", speech: SpeechSettings(cast: ["Anna": CastVoice(reference: voice("a"))]))
        #expect(try AudioCppEngine.direction(for: request, recipe: try recipe(copies: false)).samples.isEmpty)
    }

    @Test func moreSpeakersThanTheModelReadsIsRefused() throws {
        let recipe = try recipe()
        #expect(throws: EngineError.tooManySpeakers(2)) {
            try AudioCppEngine.direction(for: GenerationRequest(prompt: "A: Hi.\nB: Yo.\nC: Hey."), recipe: recipe)
        }
    }

    @Test func aRecipeNeedsAUsableSpeakerLine() throws {
        var bad = try recipe()
        try bad.validate()
        bad.speech?.speakers = .init(max: 1, line: "Speaker {n}: {text}")
        #expect(throws: (any Error).self) { try bad.validate() }
        bad.speech?.speakers = .init(max: 4, line: "Speaker: {text}")
        #expect(throws: (any Error).self) { try bad.validate() }
    }
}

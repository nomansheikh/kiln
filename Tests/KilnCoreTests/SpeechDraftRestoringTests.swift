import Foundation
import Testing
@testable import KilnCore

/// Switching the model of a draft, and putting a clip back into it.
@Suite struct SpeechDraftRestoringTests {
    private let fixture = SpeechDraftFixture()

    // MARK: - Switching the model

    @Test func theVoiceIsKeptWhenTheNewModelHasItToo() {
        var draft = fixture.draft(recipe: fixture.described(.optional), voice: "alba")
        draft.select(fixture.named)
        #expect(draft.voice == "alba")
    }

    @Test func aVoiceTheNewModelLacksBecomesItsDefault() {
        var draft = fixture.draft(recipe: fixture.named, voice: "george")
        draft.select(fixture.described(.optional))
        #expect(draft.voice == "alba")

        draft.select(fixture.copying())
        #expect(draft.voice == nil)
    }

    @Test func aLanguageTheNewModelDoesNotOfferGoesBackToAuto() {
        let german = fixture.speech(.init(family: "f", voices: ["alba"]), id: "german", languages: ["en", "de"])
        var draft = fixture.draft(recipe: nil)
        draft.language = "de"

        draft.select(german)
        #expect(draft.language == "de")

        draft.select(fixture.named)
        #expect(draft.language == nil)
    }

    @Test func switchingKeepsTheTextTheStyleAndTheCast() {
        var draft = fixture.draft("Anna: Hi.", recipe: fixture.named)
        draft.instruction = "Calm."
        draft.cast = ["anna": .named("alba")]
        draft.select(fixture.styled)
        #expect(draft.text == "Anna: Hi.")
        #expect(draft.instruction == "Calm.")
        #expect(draft.cast == ["anna": .named("alba")])
    }

    // MARK: - Putting a clip back

    @Test func aClipBringsBackItsTextModelAndVoice() {
        var draft = fixture.draft("Something else.", recipe: fixture.styled, savedVoiceID: fixture.anna.id)
        let request = GenerationRequest(prompt: "Hello.", speech: SpeechSettings(voice: "alba"))

        draft.reuse(request, madeWith: fixture.named)

        #expect(draft.text == "Hello.")
        #expect(draft.recipe?.id == "named")
        #expect(draft.voice == "alba")
        #expect(draft.savedVoiceID == nil)
    }

    @Test func aClipMadeInASavedVoiceSelectsItAgain() {
        var draft = fixture.draft(recipe: fixture.named)
        let request = GenerationRequest(
            prompt: "Hello.", speech: SpeechSettings(reference: fixture.anna.reference(in: fixture.store))
        )

        draft.reuse(request, madeWith: fixture.styled)

        #expect(draft.savedVoiceID == fixture.anna.id)
        #expect(draft.request.speech?.reference?.name == "Anna")
    }

    @Test func aClipWhoseVoiceWasDeletedKeepsTheCurrentChoice() {
        var draft = fixture.draft(recipe: fixture.styled, savedVoiceID: fixture.wordless.id)
        let gone = VoiceReference(file: URL(fileURLWithPath: "/voices/gone.wav"), transcript: nil, name: "Gone")

        draft.reuse(GenerationRequest(prompt: "Hello.", speech: SpeechSettings(reference: gone)), madeWith: fixture.styled)

        #expect(draft.savedVoiceID == fixture.wordless.id)
    }

    @Test func aScriptBringsBackTheVoicesOfItsSpeakers() {
        var draft = fixture.draft(recipe: fixture.styled)
        draft.cast = ["carl": .named("george")]
        let cast = [
            "Anna": CastVoice(reference: fixture.anna.reference(in: fixture.store)),
            "Ben": CastVoice(voice: "alba"),
            "Dora": CastVoice(reference: VoiceReference(file: URL(fileURLWithPath: "/voices/gone.wav"), transcript: nil, name: "Gone")),
        ]

        draft.reuse(GenerationRequest(prompt: "Anna: Hi.\nBen: Yo.", speech: SpeechSettings(cast: cast)), madeWith: fixture.styled)

        // Dora's voice no longer exists; Carl's choice from before is left alone.
        #expect(draft.cast == ["anna": .saved(fixture.anna.id), "ben": .named("alba"), "carl": .named("george")])
    }

    @Test func aClipBringsBackItsStyle() {
        var draft = fixture.draft(recipe: fixture.named)
        draft.reuse(
            GenerationRequest(prompt: "Hello.", speech: SpeechSettings(instruction: "elderly, high pitch")), madeWith: fixture.styled
        )
        #expect(draft.styleWords == ["elderly", "high pitch"])
        #expect(draft.instruction.isEmpty)

        draft.reuse(GenerationRequest(prompt: "Hello.", speech: SpeechSettings(instruction: "Calm.")), madeWith: fixture.described(.optional))
        #expect(draft.instruction == "Calm.")

        // A clip made without a description clears the one in the field.
        draft.reuse(GenerationRequest(prompt: "Hello.", speech: SpeechSettings(voice: "alba")), madeWith: fixture.described(.optional))
        #expect(draft.instruction.isEmpty)
    }

    @Test func aModelThatTakesNoStyleLeavesTheWrittenOneAlone() {
        var draft = fixture.draft(recipe: fixture.described(.optional))
        draft.instruction = "Calm."
        draft.reuse(GenerationRequest(prompt: "Hello.", speech: SpeechSettings(voice: "alba")), madeWith: fixture.named)
        #expect(draft.instruction == "Calm.")
    }
}

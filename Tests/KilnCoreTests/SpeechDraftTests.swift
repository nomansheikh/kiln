import Foundation
import Testing
@testable import KilnCore

/// What the Speech composer sends, and when it refuses to.
@Suite struct SpeechDraftTests {
    private let fixture = SpeechDraftFixture()
    private let dialogue = "Anna: Hi.\nBen: Yo."

    // MARK: - Whether it can be sent

    @Test func nothingIsSentWithoutAModelOrWithoutText() {
        #expect(!fixture.draft(recipe: nil).canSend)
        #expect(!fixture.draft(" \n ", recipe: fixture.named).canSend)
        #expect(fixture.draft(recipe: fixture.named).canSend)
    }

    @Test func aModelThatOnlyCopiesVoicesNeedsOne() {
        var draft = fixture.draft(recipe: fixture.copying())
        #expect(draft.voiceProblem == "This model speaks in a voice it copies. Add a voice first.")
        #expect(!draft.canSend)

        draft.savedVoiceID = fixture.anna.id
        #expect(draft.voiceProblem == nil)
        #expect(draft.canSend)
    }

    @Test func aModelThatNeedsTheWordsRefusesAVoiceWithoutThem() {
        var draft = fixture.draft(recipe: fixture.copying(text: .required), savedVoiceID: fixture.wordless.id)
        #expect(draft.voiceProblem == "This model needs the words spoken in \u{201C}Ben\u{201D} before it can copy the voice.")

        draft.recipe = fixture.copying(text: .optional)
        #expect(draft.voiceProblem == nil)
    }

    @Test func aRequiredDescriptionMustBeWritten() {
        var draft = fixture.draft(recipe: fixture.described(.required))
        draft.instruction = "  \n"
        #expect(draft.needsInstruction)
        #expect(!draft.canSend)

        draft.instruction = " A calm old man. "
        #expect(!draft.needsInstruction)
        #expect(draft.request.speech?.instruction == "A calm old man.")
    }

    // MARK: - What one voice is sent with

    @Test func aModelsVoiceIsSentByName() {
        let request = fixture.draft(" Hello. \n", recipe: fixture.named, voice: "alba").request
        #expect(request.prompt == "Hello.")
        #expect(request.speech == SpeechSettings(voice: "alba"))
    }

    @Test func aSavedVoiceTakesThePlaceOfTheModelsVoice() {
        let draft = fixture.draft(recipe: fixture.styled, voice: "alba", savedVoiceID: fixture.anna.id)
        #expect(draft.request.speech == SpeechSettings(reference: fixture.anna.reference(in: fixture.store)))
    }

    @Test func aSavedVoiceIsIgnoredByAModelThatCannotCopyOne() {
        let draft = fixture.draft(recipe: fixture.named, voice: "alba", savedVoiceID: fixture.anna.id)
        #expect(draft.savedVoice == nil)
        #expect(draft.request.speech == SpeechSettings(voice: "alba"))
    }

    @Test func aDescriptionIsNotSentToAModelThatTakesNone() {
        var draft = fixture.draft(recipe: fixture.named, voice: "alba")
        draft.instruction = "Whispering."
        #expect(draft.request.speech?.instruction == nil)
    }

    @Test func styleWordsAreSentInTheRecipesOrderAndOnlyThoseItKnows() {
        var draft = fixture.draft(recipe: fixture.styled)
        draft.styleWords = ["high pitch", "robot", "elderly"]
        draft.instruction = "ignored for a model with fixed words"
        #expect(draft.request.speech?.instruction == "elderly, high pitch")
    }

    @Test func theLanguageGoesWithTheRequest() {
        var draft = fixture.draft(recipe: fixture.named)
        draft.language = "de"
        #expect(draft.request.language == "de")
    }

    // MARK: - Scripts

    @Test func aTextWithSeveralSpeakersIsAScriptOnAnyModel() {
        #expect(fixture.draft(dialogue, recipe: fixture.named).isScript)
        #expect(!fixture.draft("Anna: Hi.", recipe: fixture.named).isScript)
        #expect(!fixture.draft(dialogue, recipe: nil).isScript)
        // A model that reads scripts itself reads everything as one.
        #expect(fixture.draft("Hi.", recipe: fixture.scripted).isScript)
    }

    @Test func aScriptSendsTheVoiceChosenForEachSpeaker() {
        var draft = fixture.draft(dialogue, recipe: fixture.styled)
        draft.cast = ["anna": .saved(fixture.anna.id), "ben": .named("alba"), "carl": .named("george")]
        let anna = CastVoice(reference: fixture.anna.reference(in: fixture.store))
        // Carl is not in the text, so his voice is not sent.
        #expect(draft.request.speech?.cast == ["Anna": anna, "Ben": CastVoice(voice: "alba")])
        #expect(draft.request.speech?.reference == nil)
    }

    @Test func aChosenVoiceThatWasDeletedIsNotSent() {
        var draft = fixture.draft(dialogue, recipe: fixture.named)
        draft.cast = ["anna": .saved(UUID())]
        #expect(draft.sentCast == nil)
    }

    @Test func speakersWithoutAChoiceShowTheModelsVoicesInTurn() {
        var draft = fixture.draft(dialogue, recipe: fixture.named, voice: "george")
        draft.cast = ["ben": .named("george")]
        #expect(draft.castVoice(of: "Ben") == CastVoice(voice: "george"))
        #expect(draft.castVoice(of: "Anna") == CastVoice(voice: "alba"))
        #expect(draft.speakerProblem == nil)
    }

    @Test func aCopyingModelNeedsAVoiceForEverySpeaker() {
        var draft = fixture.draft(dialogue, recipe: fixture.copying())
        #expect(draft.speakerProblem == "Anna and Ben have no voice yet. Choose one under Speakers.")
        // The single voice's problem is not reported for a script.
        #expect(draft.voiceProblem == nil)

        draft.cast = ["anna": .saved(fixture.anna.id)]
        #expect(draft.speakerProblem == "Ben has no voice yet. Choose one under Speakers.")
        #expect(!draft.canSend)

        draft.cast["ben"] = .saved(fixture.wordless.id)
        #expect(draft.speakerProblem == nil)
        #expect(draft.canSend)
    }

    @Test func aSpeakersVoiceNeedsItsWordsWhenTheModelDoes() {
        var draft = fixture.draft(dialogue, recipe: fixture.copying(text: .required))
        draft.cast = ["anna": .saved(fixture.anna.id), "ben": .saved(fixture.wordless.id)]
        #expect(draft.speakerProblem == "This model needs the words spoken in \u{201C}Ben\u{201D} before it can copy the voice.")
    }

    @Test func aModelThatReadsScriptsHasALimitOfSpeakers() {
        let draft = fixture.draft("A: One.\nB: Two.\nC: Three.", recipe: fixture.scripted)
        #expect(draft.speakerProblem == "This model speaks in at most 2 voices at once, and the text has 3 speakers.")
    }

    @Test func aNewSpeakerGetsTheFirstFreeNumber() {
        #expect(fixture.draft("", recipe: fixture.named).nextSpeakerName == "Speaker 1")
        #expect(fixture.draft("Speaker 1: Hi.\nspeaker 3: Yo.", recipe: fixture.named).nextSpeakerName == "Speaker 2")
    }
}

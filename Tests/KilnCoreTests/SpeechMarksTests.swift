import Foundation
import Testing
@testable import KilnCore

@Suite struct SpeechMarksTests {
    private let omni = ["[laughter]", "[sigh]", "[surprise-ah]", "[surprise-oh]", "[question-en]"]
    private let maya = ["<laugh>", "<whisper>", "<sigh>", "<gasp>"]

    @Test func aMarkIsRewrittenToTheModelsOwnSpelling() {
        #expect(SpeechMarks.apply(to: "Well [laughs] that worked.", tags: omni) == "Well [laughter] that worked.")
        #expect(SpeechMarks.apply(to: "Well [laughs] that worked.", tags: maya) == "Well <laugh> that worked.")
        #expect(SpeechMarks.apply(to: "<Laughing> Stop it. [SIGHS]", tags: omni) == "[laughter] Stop it. [sigh]")
        #expect(SpeechMarks.apply(to: "Oh [surprise] really? [surprise_oh]", tags: omni) == "Oh [surprise-ah] really? [surprise-oh]")
        #expect(SpeechMarks.apply(to: "[whispering] come closer", tags: maya) == "<whisper> come closer")
    }

    @Test func theModelsOwnMarksAreLeftAsTheyAre() {
        let text = "[laughter] Fine. [question-en] [sigh]"
        #expect(SpeechMarks.apply(to: text, tags: omni) == text)
    }

    @Test func aMarkTheModelDoesNotHaveIsLeftOut() {
        #expect(SpeechMarks.apply(to: "Well [laughs] that worked.", tags: []) == "Well that worked.")
        #expect(SpeechMarks.apply(to: "That worked [gasp].", tags: omni) == "That worked.")
        #expect(SpeechMarks.apply(to: "[coughs] Sorry.  Go on", tags: maya) == "Sorry. Go on")
        #expect(SpeechMarks.apply(to: "[laughs]", tags: []) == "")
    }

    @Test func wordsThatOnlyLookAlikeDoNotMatch() {
        #expect(SpeechMarks.tag(for: "sight", in: maya) == nil)
        #expect(SpeechMarks.tag(for: "gas", in: maya) == nil)
        #expect(SpeechMarks.tag(for: "laundry", in: omni) == nil)
        #expect(SpeechMarks.tag(for: "sighing", in: maya) == "<sigh>")
    }

    @Test func marksAreFoundWithTheirPlaceAndWhetherTheModelHasThem() {
        // The emoji is two UTF-16 units, which is how a text view counts.
        let marks = SpeechMarks.marks(in: "😀 [laughs] ok <gasp>", tags: omni)

        #expect(marks == [
            .init(range: NSRange(location: 3, length: 8), written: "[laughs]", tag: "[laughter]"),
            .init(range: NSRange(location: 15, length: 6), written: "<gasp>", tag: nil),
        ])
        #expect(SpeechMarks.marks(in: "Nothing [1] here", tags: omni).isEmpty)
    }

    @Test func otherBracketsAreOrdinaryText() {
        for text in ["See note [1] and [citation needed].", "[S1] Hello. [S2] Hi.", "if a < b and b > c", "Speaker 1: Hi", "two  spaces stay"] {
            #expect(SpeechMarks.apply(to: text, tags: omni) == text)
            #expect(SpeechMarks.apply(to: text, tags: []) == text)
        }
    }
}

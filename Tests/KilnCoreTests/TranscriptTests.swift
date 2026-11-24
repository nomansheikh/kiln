import Foundation
import Testing
@testable import KilnCore

@Suite struct TranscriptTests {
    private let talk = Transcript(segments: [
        .init(start: 0, end: 2.5, text: " Good morning."),
        .init(start: 2.5, end: 3725.04, text: " And goodbye."),
    ])

    @Test func segmentsLoseTheirLeadingSpaceAndEmptyOnesAreDropped() {
        let transcript = Transcript(segments: [
            .init(start: 0, end: 1, text: " Hello."), .init(start: 1, end: 2, text: "  \n"), .init(start: 2, end: 3, text: " Bye."),
        ])
        #expect(transcript.segments.map(\.text) == ["Hello.", "Bye."])
        #expect(transcript.text == "Hello. Bye.")
    }

    @Test func aSegmentNeverEndsBeforeItStarts() {
        #expect(Transcript(segments: [.init(start: 5, end: 3, text: "Hi.")]).segments.first?.end == 5)
    }

    @Test func aRecordingWithoutSpeechIsEmpty() {
        let transcript = Transcript(segments: [.init(start: 0, end: 4, text: " ")])
        #expect(transcript.isEmpty)
        #expect(transcript.text.isEmpty)
    }

    @Test func timesAreOnlyWorthShowingForSeveralSegments() {
        #expect(talk.hasTimes)
        #expect(!Transcript(segments: [.init(start: 0, end: 4, text: "Hi.")]).hasTimes)
    }

    @Test func theSegmentAtATimeIsTheLastOneThatHasStarted() {
        let transcript = Transcript(segments: [
            .init(start: 1, end: 3, text: "One."), .init(start: 3, end: 5, text: "Two."), .init(start: 8, end: 9, text: "Three."),
        ])
        #expect(transcript.segmentIndex(at: 0.5) == nil)
        #expect(transcript.segmentIndex(at: 1) == 0)
        #expect(transcript.segmentIndex(at: 3) == 1)
        // A pause between two segments still belongs to the one before it.
        #expect(transcript.segmentIndex(at: 6) == 1)
        #expect(transcript.segmentIndex(at: 60) == 2)
    }

    @Test func segmentsArrivingOneByOneFollowTheSameRules() {
        var transcript = Transcript(segments: [])
        transcript.append(.init(start: 0, end: 1, text: " Hello."))
        transcript.append(.init(start: 1, end: 2, text: "   "))
        transcript.append(.init(start: 2, end: 4.5, text: " Bye."))
        #expect(transcript == Transcript(segments: [.init(start: 0, end: 1, text: "Hello."), .init(start: 2, end: 4.5, text: "Bye.")]))
        #expect(transcript.duration == 4.5)
    }

    @Test func aLongPauseStartsANewParagraph() {
        let transcript = Transcript(segments: [
            .init(start: 0, end: 3, text: "One."), .init(start: 3.5, end: 5, text: "Two."), .init(start: 9, end: 10, text: "Three."),
        ])
        #expect(!transcript.startsParagraph(at: 0))
        #expect(!transcript.startsParagraph(at: 1))
        #expect(transcript.startsParagraph(at: 2))
        #expect(!transcript.startsParagraph(at: 7))
    }

    @Test func aTimeReadsAsOnAPlayer() {
        #expect(Transcript.clock(0) == "0:00")
        #expect(Transcript.clock(7.9) == "0:07")
        #expect(Transcript.clock(750) == "12:30")
        #expect(Transcript.clock(3723) == "1:02:03")
        #expect(Transcript.clock(-2) == "0:00")
    }

    @Test func subRipNumbersItsCuesAndUsesAComma() {
        #expect(talk.subtitles(.srt) == """
        1
        00:00:00,000 --> 00:00:02,500
        Good morning.

        2
        00:00:02,500 --> 01:02:05,040
        And goodbye.

        """)
    }

    @Test func webVTTStartsWithItsHeaderAndUsesAFullStop() {
        #expect(talk.subtitles(.vtt) == """
        WEBVTT

        00:00:00.000 --> 00:00:02.500
        Good morning.

        00:00:02.500 --> 01:02:05.040
        And goodbye.

        """)
    }

    @Test func theHelpersFileIsReadWithItsTimesInSeconds() {
        let file = Data(#"{"segments":[{"start_ms":0,"end_ms":3000,"text":" Good morning."},{"start_ms":3000,"end_ms":6250,"text":" Hi."}]}"#.utf8)
        #expect(EngineMessage.transcript(from: file) == Transcript(segments: [
            .init(start: 0, end: 3, text: "Good morning."), .init(start: 3, end: 6.25, text: "Hi."),
        ]))
    }

    @Test func aFileThatIsNotATranscriptIsRefused() {
        #expect(EngineMessage.transcript(from: Data("Good morning.".utf8)) == nil)
        #expect(EngineMessage.transcript(from: Data(#"{"words":[]}"#.utf8)) == nil)
    }

    @Test func aTranscriptIsSavedAsPlainTextTooForOlderVersions() throws {
        let turn = GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, state: .transcript(talk))
        #expect(turn.saved.outcome == .text("Good morning. And goodbye."))
        #expect(turn.saved.segments == talk.segments)
        // A chat saved before segments existed has none, and stays plain text.
        let old = try JSONDecoder().decode(ChatTurn.self, from: JSONEncoder().encode(ChatTurn(prompt: "", kind: .text, outcome: .text("Hi."))))
        #expect(old.segments == nil)
    }
}

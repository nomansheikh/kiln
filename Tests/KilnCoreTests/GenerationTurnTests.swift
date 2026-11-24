import Foundation
import Testing
@testable import KilnCore

/// A thread's turns, and their saved form.
@Suite struct GenerationTurnTests {
    private let attachments = AttachmentLibrary(directory: URL(fileURLWithPath: "/attachments"))
    private let record = GenerationRecord(
        recipeID: "r", recipeName: "R",
        request: GenerationRequest(prompt: "A fox.", defaults: .init(steps: 8, cfg: 1, sampler: "euler", width: 1024, height: 512), seed: 1),
        durationSeconds: 2
    )

    private var picture: GalleryItem { GalleryItem(url: URL(fileURLWithPath: "/gallery/fox.png"), record: record) }
    private var sound: AudioItem { AudioItem(url: URL(fileURLWithPath: "/audio/fox.wav"), record: record, durationSeconds: 3) }

    private func restored(_ turn: GenerationTurn, images: [GalleryItem] = [], sounds: [AudioItem] = []) -> GenerationTurn {
        GenerationTurn(turn.saved, images: images, sounds: sounds, attachments: attachments)
    }

    @Test func aTurnBuiltFromAnImageTakesItsPromptAndSize() {
        let turn = GenerationTurn(picture)
        #expect(turn.id == record.id)
        #expect(turn.prompt == "A fox.")
        #expect(turn.kind == .image)
        #expect(turn.image == picture)
        #expect(turn.aspectRatio == 2)
    }

    @Test func aTurnWithoutASizeIsSquare() {
        #expect(GenerationTurn(prompt: "Hi.", kind: .audio, width: nil, height: nil).aspectRatio == 1)
        #expect(GenerationTurn(prompt: "Hi.", width: 0, height: 0).aspectRatio == 1)
    }

    @Test func everyOutcomeSurvivesBeingSaved() {
        let attachment = attachments.url(named: "id-talk.mp3")
        let turns = [
            GenerationTurn(prompt: "A fox.", width: 1024, height: 512, state: .finished(picture)),
            GenerationTurn(prompt: "", kind: .text, width: nil, height: nil, attachment: attachment, state: .text("Hello.")),
            GenerationTurn(
                prompt: "", kind: .text, width: nil, height: nil, attachment: attachment,
                state: .transcript(Transcript(segments: [
                    .init(start: 0, end: 2.5, text: "Hello."), .init(start: 2.5, end: 4, text: "How are you?"),
                ]))
            ),
            GenerationTurn(prompt: "Hello.", kind: .audio, width: nil, height: nil, state: .audio(sound)),
            GenerationTurn(prompt: "A fox.", width: 512, height: 512, state: .failed("It ran out of memory.")),
            GenerationTurn(prompt: "A fox.", width: 512, height: 512, state: .cancelled),
        ]
        for turn in turns {
            #expect(restored(turn, images: [picture], sounds: [sound]) == turn)
        }
    }

    @Test func aTurnStillRunningIsSavedAsStopped() {
        let turn = GenerationTurn(prompt: "A fox.", width: 512, height: 512)
        #expect(turn.saved.outcome == .cancelled)
        #expect(restored(turn).state == .cancelled)
    }

    @Test func aResultThatWasDeletedIsSaidToBeGone() {
        let image = GenerationTurn(prompt: "A fox.", width: 512, height: 512, state: .finished(picture))
        #expect(restored(image).state == .failed("This image is no longer in the Gallery."))

        let clip = GenerationTurn(prompt: "Hello.", kind: .audio, width: nil, height: nil, state: .audio(sound))
        #expect(restored(clip).state == .failed("This audio file is no longer on this Mac."))
    }

    @Test func aTurnSavedBeforeKindsExistedIsAnImage() {
        let old = ChatTurn(prompt: "A fox.", outcome: .cancelled)
        #expect(GenerationTurn(old, images: [], sounds: [], attachments: attachments).kind == .image)
    }
}

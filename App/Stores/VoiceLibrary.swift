import Foundation
import KilnCore
import Observation

/// The user's own voices on disk: recordings a model can copy a voice from.
@MainActor
@Observable
final class VoiceLibrary {
    let store: VoiceStore
    private(set) var voices: [SavedVoice] = []

    init(store: VoiceStore) {
        self.store = store
        reload()
    }

    func reload() {
        voices = store.voices()
    }

    @discardableResult
    func add(recording: URL, name: String, transcript: String, design: String? = nil) throws -> SavedVoice {
        let voice = try store.add(recording: recording, name: name, transcript: transcript, design: design)
        reload()
        return voice
    }

    func update(_ voice: SavedVoice) throws {
        try store.update(voice)
        reload()
    }

    func delete(_ voice: SavedVoice) throws {
        try store.delete(voice)
        reload()
    }
}

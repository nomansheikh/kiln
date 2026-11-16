import Foundation
import KilnCore

/// A script: a text with several speakers, each read in a voice of their own.
/// A model that reads scripts gets the whole text; any other reads it turn by turn.
extension SpeechStore {
    typealias CastChoice = SpeechDraft.CastChoice

    func choose(_ choice: CastChoice?, for speaker: String) {
        cast[SpeechScript.key(speaker)] = choice
    }

    /// Opens the sheet for adding or designing a voice, which then becomes that speaker's.
    func addVoice(for speaker: String, designing: Bool) {
        editedVoiceID = nil
        if designing { isDesigningVoice = true } else { isAddingVoice = true }
        pendingSpeaker = speaker
    }
}

import Foundation
import KilnCore
import Observation

/// The Speech screen's state: the text being written, the voice it will be
/// read in, and the clip that is loaded in the player.
@MainActor
@Observable
final class SpeechStore {
    var text = ""
    private(set) var recipeID: String?
    var voice: String?
    /// The chosen voice of the user's own, which takes the place of `voice`.
    var savedVoiceID: UUID?
    /// True while the sheet for adding or changing a voice is open, and the voice being changed.
    var isAddingVoice = false {
        didSet { if !isAddingVoice { pendingSpeaker = nil } }
    }
    var editedVoiceID: UUID?
    /// True while the sheet for designing a voice is open. See `SpeechStore+Design`.
    var isDesigningVoice = false {
        didSet { if !isDesigningVoice { pendingSpeaker = nil } }
    }
    /// The voices chosen for the speakers of a script, by speaker name, and the
    /// speaker a voice being added is for. See `SpeechStore+Speakers`.
    var cast: [String: CastChoice] = [:]
    var pendingSpeaker: String?
    /// Code of the language to speak in. Nil lets the model decide.
    var language: String?
    /// A description of the voice or the delivery. Kept across models, and sent
    /// only to one that takes it.
    var instruction = ""
    /// The words chosen for a model that takes fixed style words instead.
    var styleWords: [String] = []
    private(set) var activity = Activity.idle
    /// The clip that is playing or was played last.
    private(set) var current: AudioItem?
    private(set) var playback: AudioPlayback?
    /// Each clip's outline, for drawing its waveform, read when it is first shown.
    private(set) var peaks: [UUID: [Float]] = [:]
    /// Playback speed for every clip, where 1 is the sound as it was made.
    var rate: Float = 1 {
        didSet { playback?.rate = rate }
    }
    var errorMessage: String?

    /// The voice whose sample is being made, and the one whose sample is loaded. See `SpeechStore+Preview`.
    var preparingPreview: String?
    var previewVoice: String?
    var previewPlayback: AudioPlayback?

    /// True while another screen is using the engine. Only one model runs at a time.
    var isEngineBusyElsewhere: () -> Bool = { false }

    let library: ModelLibrary
    let audio: AudioLibrary
    let voices: VoiceLibrary
    let engine: any InferenceEngine
    private var task: Task<Void, Never>?

    init(library: ModelLibrary, audio: AudioLibrary, voices: VoiceLibrary, engine: any InferenceEngine) {
        self.library = library
        self.audio = audio
        self.voices = voices
        self.engine = engine
        selectDefaultRecipeIfNeeded()
    }

    // MARK: - Model and voice

    /// Installed models that read text aloud.
    var recipes: [ModelRecipe] {
        library.installedRecipes.filter { $0.task == .textToSpeech }
    }

    var selectedRecipe: ModelRecipe? {
        recipes.first { $0.id == recipeID }
    }

    var isGenerating: Bool { activity != .idle }

    /// True while this screen has the engine, for a clip or for a voice sample.
    var isUsingEngine: Bool { isGenerating || preparingPreview != nil }

    /// Roughly how long the text takes to say. Speech runs at about 16 characters a second.
    var estimatedSeconds: Double {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines).count) / 16
    }

    var canGenerate: Bool {
        !isUsingEngine && !isEngineBusyElsewhere() && draft.canSend
    }

    func selectRecipe(_ recipe: ModelRecipe?) {
        var draft = draft
        draft.select(recipe)
        apply(draft)
    }

    func setRecipe(_ recipe: ModelRecipe?) {
        recipeID = recipe?.id
    }

    /// Picks an installed voice model when the current choice is missing or was deleted.
    func selectDefaultRecipeIfNeeded() {
        if selectedRecipe != nil { return }
        selectRecipe(recipes.first)
    }

    // MARK: - Generating

    /// Sends the text to be read aloud: the field empties, and the clip plays when it is ready.
    func generate() {
        guard canGenerate, let recipe = selectedRecipe else { return }
        let sent = text
        let request = draft.request
        text = ""
        errorMessage = nil
        playback?.pause()
        activity = .loadingModel
        task = Task {
            let started = Date()
            var madeClip = false
            do {
                for try await event in engine.speak(recipe: recipe, request: request) {
                    switch event {
                    case .loadingModel: activity = .loadingModel
                    case .progress: activity = .speaking
                    case .preview: break
                    case .finished(.audio(let sound)):
                        let record = GenerationRecord(
                            recipeID: recipe.id, recipeName: recipe.name, request: request,
                            durationSeconds: Date().timeIntervalSince(started)
                        )
                        show(try audio.add(sound, record: record))
                        playback?.play()
                        madeClip = true
                    case .finished:
                        errorMessage = "The model did not produce audio."
                    }
                }
                // A stream whose consumer was cancelled ends quietly instead of throwing.
                if Task.isCancelled, !madeClip { restore(sent) }
            } catch is CancellationError {
                restore(sent)
            } catch {
                restore(sent)
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            activity = .idle
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Puts text that produced no clip back in the field, unless something new was typed meanwhile.
    private func restore(_ sent: String) {
        if text.isEmpty { text = sent }
    }

    // MARK: - Clips

    /// Makes a clip the one the player controls act on.
    func show(_ item: AudioItem) {
        guard item.id != current?.id else { return }
        playback?.pause()
        current = item
        let player = AudioPlayback(url: item.url, duration: item.durationSeconds)
        player.rate = rate
        playback = player
    }

    /// Reads a clip's outline from its file, once.
    func loadPeaks(for item: AudioItem) async {
        guard peaks[item.id] == nil else { return }
        let url = item.url
        peaks[item.id] = await Task.detached { AudioWaveform.peaks(of: url, count: 400) }.value
    }

    /// Moves playback to a point in a clip, from 0 to 1, loading the clip first if needed.
    func seek(_ item: AudioItem, to fraction: Double) {
        show(item)
        playback?.seek(to: fraction * item.durationSeconds)
    }

    /// Loads a clip and plays it, or pauses it when it is the one playing.
    func togglePlayback(of item: AudioItem) {
        if item.id == current?.id {
            playback?.toggle()
        } else {
            show(item)
            playback?.play()
        }
    }

    /// Puts a clip's text and voice back in the editor.
    func reuse(_ item: AudioItem) {
        var draft = draft
        if let recipe = recipes.first(where: { $0.id == item.record.recipeID }) {
            draft.reuse(item.record.request, madeWith: recipe)
        } else {
            draft.text = item.record.request.prompt
        }
        apply(draft)
    }

    func delete(_ item: AudioItem) {
        if item.id == current?.id {
            playback?.pause()
            current = nil
            playback = nil
        }
        peaks[item.id] = nil
        do {
            try audio.delete(item)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// Fills the screen with sample content for snapshots.
    func loadPreview(text: String, current: AudioItem?) {
        self.text = text
        if let current { show(current) }
    }

    /// Shows the screen as it is while a clip is being made.
    func loadPreview(activity: Activity) {
        self.activity = activity
    }
    #endif
}

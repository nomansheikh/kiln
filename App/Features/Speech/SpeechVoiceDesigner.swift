import KilnCore
import SwiftUI

/// The sheet for designing a voice: a model that can make one up from a
/// description speaks a sample, and the sample is kept as one of the user's
/// own voices for any model that copies voices.
struct SpeechVoiceDesigner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recipeID: String?
    @State private var name = ""
    /// The chosen words, for a model with fixed ones, and the description, for one that takes any.
    @State private var words: [String] = []
    @State private var description = ""
    @State private var sample = "The weather was calm that morning, so we walked down to the harbour and watched the boats come in."
    @State private var sound: GeneratedAudio?
    @State private var playback: AudioPlayback?
    @State private var isWorking = false
    @State private var problem: String?

    private var recipe: ModelRecipe? {
        model.speech.designers.first { $0.id == recipeID } ?? model.speech.designers.first
    }

    /// What the model is told the voice is like.
    private var design: String {
        recipe?.speech?.styles != nil ? words.joined(separator: ", ") : description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Design a Voice")
                    .font(.title3.weight(.semibold))
                Text("Describe a voice and a model makes it up. Keep the one you like: it is saved with your voices, and every model that copies voices can speak in it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let recipe {
                form(for: recipe)
            } else {
                Text("No installed model can make up a voice. OmniVoice can; get it from Models.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Get a Model\u{2026}") {
                    dismiss()
                    model.browseModels(for: .textToSpeech)
                }
                .buttonStyle(SoftButtonStyle())
            }

            if let problem {
                Text(problem)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save Voice", action: save)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(sound == nil || isBlank(name) || isWorking)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDisappear { playback?.pause() }
        #if DEBUG
        .onAppear {
            // A snapshot shows the sheet with a few traits chosen.
            guard DebugSnapshot.outputDirectory != nil, let groups = recipe?.speech?.styles else { return }
            words = groups.prefix(2).compactMap(\.options.first)
        }
        #endif
    }

    @ViewBuilder
    private func form(for recipe: ModelRecipe) -> some View {
        if model.speech.designers.count > 1 {
            Picker("Made by", selection: Binding(get: { recipe.id }, set: { recipeID = $0; sound = nil; words = [] })) {
                ForEach(model.speech.designers) { Text(verbatim: $0.name).tag($0.id) }
            }
            .fixedSize()
        }
        field("Name") {
            TextField("For example: Narrator", text: $name)
        }
        if let groups = recipe.speech?.styles {
            VStack(alignment: .leading, spacing: 5) {
                Text("What the voice is like")
                    .font(.callout.weight(.medium))
                SpeechTraitPicker(groups: groups, chosen: $words)
            }
        } else {
            field("What the voice is like") {
                TextField("For example: a warm, low male voice, unhurried", text: $description, axis: .vertical)
                    .lineLimit(2...4)
            }
        }
        field("What it says in the sample") {
            TextField("A sentence or two", text: $sample, axis: .vertical)
                .lineLimit(2...4)
        }
        HStack(spacing: 10) {
            Button(sound == nil ? "Make a Sample" : "Make Another", action: make)
                .buttonStyle(SoftButtonStyle())
                .disabled(design.isEmpty || isBlank(sample) || isWorking)
            if isWorking {
                ProgressView().controlSize(.small)
            } else if let playback {
                Button { playback.toggle() } label: {
                    Label(playback.isPlaying ? "Pause" : "Play", systemImage: playback.isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(SoftButtonStyle())
            }
            Spacer()
        }
        Text("Each sample is a new voice, even with the same description. Make samples until one sounds right.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.medium))
            content()
                .textFieldStyle(.plain)
                .padding(9)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private func make() {
        guard let recipe else { return }
        isWorking = true
        problem = nil
        playback?.pause()
        Task {
            defer { isWorking = false }
            do {
                let made = try await model.speech.designSample(
                    with: recipe, description: design, words: sample.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                // The player reads a file, so the sample is kept in one while the sheet is open.
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-design-sample.wav")
                try made.wavData().write(to: file)
                sound = made
                playback = AudioPlayback(url: file, duration: made.durationSeconds)
                playback?.play()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func save() {
        guard let sound else { return }
        do {
            try model.speech.saveDesigned(
                sound, name: name, description: design, words: sample.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            dismiss()
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

import KilnCore
import SwiftUI
import UniformTypeIdentifiers

/// The sheet for adding a voice, or changing one: a recording of someone
/// speaking, a name for it, and the words spoken in it.
struct SpeechVoiceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var recording: URL?
    @State private var name = ""
    @State private var transcript = ""
    @State private var choosesFile = false
    @State private var isTranscribing = false
    /// The language the recording is in, for writing its words down. Nil lets the model decide.
    @State private var language: String?
    @State private var problem: String?

    /// The voice being changed, or nil when a new one is being added.
    private var edited: SavedVoice? { model.speech.editedVoice }

    var body: some View {
        let needsWords = model.speech.selectedRecipe?.speech?.referenceText == .required
        let seconds = Int(AudioSamples.referenceSeconds)

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(edited == nil ? "Add a Voice" : "Edit Voice")
                    .font(.title3.weight(.semibold))
                Text("A voice is copied from a recording of one person speaking clearly, without music or noise. Only the first \(seconds) seconds are used.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if edited == nil {
                HStack(spacing: 10) {
                    Button(recording == nil ? "Choose Recording\u{2026}" : "Choose Another\u{2026}") { choosesFile = true }
                        .buttonStyle(SoftButtonStyle())
                    if let recording {
                        Label(recording.lastPathComponent, systemImage: "waveform")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            field("Name") {
                TextField("For example: My voice", text: $name)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(needsWords ? "Words in the first \(seconds) seconds" : "Words in the first \(seconds) seconds (optional)")
                        .lineLimit(1)
                        .font(.callout.weight(.medium))
                    Spacer()
                    if isTranscribing {
                        ProgressView().controlSize(.small)
                    }
                    if let languages = model.speech.transcriber?.languages, languages.count > 1 {
                        GenerationLanguageMenu(languages: languages, selection: $language)
                    }
                    Button("Write Them for Me", action: transcribe)
                        .buttonStyle(SoftButtonStyle())
                        .controlSize(.small)
                        .disabled(source == nil || isTranscribing)
                        .help("Listens to the recording with an installed speech-to-text model. Choose the language first if it guesses wrong, and check the result.")
                }
                TextField("Type exactly what is said", text: $transcript, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(9)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(needsWords
                    ? "The selected model cannot copy a voice without these words."
                    : "Some models copy a voice better, or only, when they know the words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Only add a voice you have the right to use. A copied voice can pass for the real person.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                Button(edited == nil ? "Add Voice" : "Save", action: save)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(source == nil || isBlank(name) || (needsWords && isBlank(transcript)) || isTranscribing)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            language = model.speech.language
            guard let edited else { return }
            name = edited.name
            transcript = edited.transcript
        }
        .fileImporter(isPresented: $choosesFile, allowedContentTypes: [.audio]) { result in
            guard case .success(let file) = result else { return }
            recording = file
            problem = nil
            if name.isEmpty { name = file.deletingPathExtension().lastPathComponent }
        }
    }

    /// The recording the sheet is about: the saved one, or the file just chosen.
    private var source: URL? {
        edited.map { model.speech.voices.store.recording(of: $0) } ?? recording
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

    private func transcribe() {
        guard let source else { return }
        isTranscribing = true
        problem = nil
        Task {
            defer { isTranscribing = false }
            do {
                // A file picked in the open panel may need opening first.
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let words = try await model.speech.transcribe(source, language: language)
                if words.isEmpty {
                    problem = "No words were heard in the first \(Int(AudioSamples.referenceSeconds)) seconds."
                } else {
                    transcript = words
                }
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func save() {
        Task {
            do {
                if let edited {
                    try model.speech.updateVoice(edited, name: name, transcript: transcript)
                } else if let recording {
                    let scoped = recording.startAccessingSecurityScopedResource()
                    defer { if scoped { recording.stopAccessingSecurityScopedResource() } }
                    try model.speech.addVoice(recording: recording, name: name, transcript: transcript)
                }
                dismiss()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

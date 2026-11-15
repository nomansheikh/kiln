import KilnCore
import SwiftUI

/// The part of the voice list with the user's own voices, shown for a model
/// that can copy a voice from a recording.
struct SpeechSavedVoices: View {
    @Environment(AppModel.self) private var model
    /// Whether the model also has voices of its own, listed above.
    let hasModelVoices: Bool
    let dismiss: () -> Void

    var body: some View {
        let speech = model.speech
        let needsOne = speech.selectedRecipe?.speech?.reference == .required

        if !hasModelVoices, !needsOne {
            // A model without named voices picks one by itself unless it is given one.
            row(name: "Model's own voice", detail: "The model chooses", isSelected: speech.savedVoice == nil) {
                speech.savedVoiceID = nil
                dismiss()
            }
        }
        if hasModelVoices || !speech.voices.voices.isEmpty {
            Text("My voices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 2)
        }
        ForEach(speech.voices.voices) { voice in
            row(name: voice.name, detail: nil, isSelected: speech.savedVoice?.id == voice.id) {
                speech.savedVoiceID = voice.id
                dismiss()
            }
            .contextMenu {
                Button("Edit\u{2026}") {
                    dismiss()
                    speech.edit(voice)
                }
                Button("Delete Voice", role: .destructive) { speech.deleteVoice(voice) }
            }
        }
        Button {
            dismiss()
            speech.editedVoiceID = nil
            speech.isAddingVoice = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Theme.card, in: Circle())
                Text("Add a voice\u{2026}")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private func row(name: String, detail: String?, isSelected: Bool, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                VoiceAvatar(name: name, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
            .background(isSelected ? Theme.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

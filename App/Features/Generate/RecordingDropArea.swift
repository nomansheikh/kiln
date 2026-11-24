import KilnCore
import SwiftUI

/// Where the prompt field would be, for a model that takes a recording and not words:
/// a place to drop a file or pick one, and a button that records from the microphone.
struct RecordingDropArea: View {
    /// Whether a file is being dragged over the composer.
    let isTargeted: Bool
    let recorder: MicrophoneRecorder
    let choose: () -> Void
    /// Called with the file of a finished recording.
    let recorded: (URL) -> Void

    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        Group {
            if recorder.isRecording {
                recording
            } else {
                HStack(spacing: 10) {
                    Button(action: choose) { invitation }
                        .buttonStyle(PressableButtonStyle(scale: 0.99))
                        .pointerCursor()
                        .onHover { hovering = $0 }
                        .accessibilityLabel("Choose a recording to turn into text")
                    Button {
                        Task { await recorder.start() }
                    } label: {
                        Label("Record", systemImage: "mic.fill")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .pointerCursor()
                    .hint("Record from the microphone")
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .background(fill, in: shape)
        .overlay(
            shape.strokeBorder(
                isTargeted || recorder.isRecording ? Theme.accent : Color.primary.opacity(0.16),
                style: StrokeStyle(lineWidth: 1.2, dash: isTargeted || recorder.isRecording ? [] : [5, 4])
            )
        )
        .onDisappear { recorder.cancel() }
    }

    private var fill: Color {
        if isTargeted || recorder.isRecording { return Theme.accent.opacity(0.08) }
        return Color.primary.opacity(hovering ? 0.045 : 0.025)
    }

    private var invitation: some View {
        HStack(spacing: 14) {
            Image(systemName: isTargeted ? "arrow.down" : "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .contentTransition(.symbolEffect(.replace))
            VStack(alignment: .leading, spacing: 3) {
                Text(isTargeted ? "Drop it to attach" : "Drop a recording here")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                Text("or click to choose an audio file")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 76)
        .contentShape(Rectangle())
    }

    private var recording: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .frame(width: 44, height: 44)
                .background(Color.red.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Recording")
                    .font(.system(size: 15, weight: .medium))
                Text(Transcript.clock(recorder.elapsed))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            RecordingMeter(levels: recorder.levels, length: MicrophoneRecorder.meterLength)
                .frame(maxWidth: .infinity)
            Button("Cancel") { recorder.cancel() }
                .buttonStyle(SoftButtonStyle())
            Button {
                if let file = recorder.finish() { recorded(file) }
            } label: {
                Label("Done", systemImage: "stop.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .keyboardShortcut(.defaultAction)
            .hint("Stop and attach the recording")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording, \(Transcript.clock(recorder.elapsed))")
    }
}

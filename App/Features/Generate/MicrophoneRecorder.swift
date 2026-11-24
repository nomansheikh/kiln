import AVFoundation
import KilnCore
import Observation

/// Records from the microphone into a file, for a model that turns speech into text.
/// Nothing is recorded until `start` is called, and the file never leaves this Mac.
@MainActor
@Observable
final class MicrophoneRecorder {
    private(set) var isRecording = false
    /// Seconds recorded so far.
    private(set) var elapsed: TimeInterval = 0
    /// The loudness of the last few seconds, oldest first, each from 0 to 1.
    private(set) var levels: [Double] = []
    /// Why recording could not start, in words for the user.
    var errorMessage: String?

    /// How many readings the meter keeps: a few seconds at the pace of `tick`.
    static let meterLength = 48

    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    /// Asks for the microphone if it has not been asked before, then starts recording.
    func start() async {
        guard !isRecording else { return }
        guard await Self.mayUseMicrophone() else {
            errorMessage = "Kiln is not allowed to use the microphone. Allow it in System Settings, under Privacy & Security, Microphone."
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("kiln-recordings", isDirectory: true)
            .appendingPathComponent(MicrophoneRecording.fileName(at: Date()))
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let made = try AVAudioRecorder(url: file, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            made.isMeteringEnabled = true
            guard made.record() else { throw CocoaError(.fileWriteUnknown) }
            recorder = made
            isRecording = true
            elapsed = 0
            levels = []
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(80))
                    self?.tick()
                }
            }
        } catch {
            errorMessage = "The microphone could not be started. Check that one is connected and try again."
        }
    }

    /// Ends the recording and hands back its file, which the caller owns from then on.
    func finish() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        reset()
        return recorder.url
    }

    /// Ends the recording and throws it away.
    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        reset()
    }

    private func tick() {
        guard let recorder, isRecording else { return }
        recorder.updateMeters()
        elapsed = recorder.currentTime
        levels.append(MicrophoneRecording.level(decibels: recorder.averagePower(forChannel: 0)))
        if levels.count > Self.meterLength { levels.removeFirst(levels.count - Self.meterLength) }
    }

    private func reset() {
        ticker?.cancel()
        ticker = nil
        recorder = nil
        isRecording = false
    }

    private static func mayUseMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .audio)
        default: false
        }
    }
}

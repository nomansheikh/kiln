import AVFoundation
import Observation

/// Plays one sound file and reports where playback is, for a player in the thread.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    /// Seconds from the start of the sound.
    private(set) var position: TimeInterval = 0
    private(set) var duration: TimeInterval
    /// Playback speed, where 1 is the sound as it was made.
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }

    private let url: URL
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    /// - Parameter duration: The sound's known length, shown before the file is opened.
    init(url: URL, duration: TimeInterval) {
        self.url = url
        self.duration = duration
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let player = loadedPlayer() else { return }
        // Starting one sound stops whichever other one was playing.
        Self.current?.pause()
        Self.current = self
        if player.currentTime >= player.duration { player.currentTime = 0 }
        guard player.play() else { return }
        isPlaying = true
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, self.isPlaying else { return }
                self.position = self.player?.currentTime ?? 0
            }
        }
    }

    func pause() {
        player?.pause()
        stopTicking()
        position = player?.currentTime ?? position
    }

    /// Moves playback to a point in the sound, playing or not.
    func seek(to seconds: TimeInterval) {
        guard let player = loadedPlayer() else { return }
        player.currentTime = max(0, min(seconds, player.duration))
        position = player.currentTime
    }

    /// Jumps forward, or back with a negative number of seconds.
    func skip(by seconds: TimeInterval) {
        seek(to: position + seconds)
    }

    private func loadedPlayer() -> AVAudioPlayer? {
        if let player { return player }
        guard let loaded = try? AVAudioPlayer(contentsOf: url) else { return nil }
        loaded.delegate = self
        loaded.enableRate = true
        loaded.rate = rate
        loaded.prepareToPlay()
        duration = loaded.duration
        player = loaded
        return loaded
    }

    private func stopTicking() {
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopTicking()
            self.position = 0
        }
    }

    /// The sound that is playing, so that only one plays at a time.
    private static weak var current: AudioPlayback?
}

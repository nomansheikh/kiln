import Foundation

/// How fast a download is going and how long it has left.
struct DownloadSpeed: Equatable {
    let bytesPerSecond: Double
    let secondsRemaining: Double?

    /// For example "12.4 MB/s".
    var speedText: String {
        Int64(bytesPerSecond).formatted(.byteCount(style: .file)) + "/s"
    }

    /// For example "About 8 minutes left". Rounded to one unit; an estimate does not deserve more.
    var remainingText: String? {
        guard let secondsRemaining else { return nil }
        guard secondsRemaining >= 5 else { return "A few seconds left" }
        let duration = Duration.seconds(Int(secondsRemaining.rounded()))
        let text = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
        return "About \(text) left"
    }

    /// Speed and time left on one line.
    var summary: String {
        [speedText, remainingText].compactMap { $0 }.joined(separator: " · ")
    }
}

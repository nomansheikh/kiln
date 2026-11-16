import Foundation

/// How fast a download is going and how long it has left.
public struct DownloadSpeed: Equatable, Sendable {
    public let bytesPerSecond: Double
    public let secondsRemaining: Double?

    public init(bytesPerSecond: Double, secondsRemaining: Double?) {
        self.bytesPerSecond = bytesPerSecond
        self.secondsRemaining = secondsRemaining
    }

    /// For example "12.4 MB/s".
    public var speedText: String {
        Int64(bytesPerSecond).formatted(.byteCount(style: .file)) + "/s"
    }

    /// For example "About 8 minutes left". Rounded to one unit; an estimate does not deserve more.
    public var remainingText: String? {
        guard let secondsRemaining else { return nil }
        guard secondsRemaining >= 5 else { return "A few seconds left" }
        let duration = Duration.seconds(Int(secondsRemaining.rounded()))
        let text = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
        return "About \(text) left"
    }

    /// The compact form, for example "4 min left".
    public var shortRemainingText: String? {
        guard let secondsRemaining else { return nil }
        guard secondsRemaining >= 5 else { return "a few sec left" }
        let duration = Duration.seconds(Int(secondsRemaining.rounded()))
        let text = duration.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
        return "\(text) left"
    }

    /// Speed and time left on one line.
    public var summary: String {
        [speedText, remainingText].compactMap { $0 }.joined(separator: " · ")
    }
}

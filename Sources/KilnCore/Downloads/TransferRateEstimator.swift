import Foundation

/// Estimates download speed and time remaining from recent progress samples.
///
/// The speed is the average over a short sliding window, which keeps the
/// estimate steady without lagging far behind a real change in speed.
public struct TransferRateEstimator: Sendable {
    private struct Sample: Sendable {
        let time: TimeInterval
        let bytes: Int64
    }

    private var samples: [Sample] = []
    private let window: TimeInterval
    /// Shortest span of samples trusted to give a speed.
    private let minimumSpan: TimeInterval = 1

    public init(window: TimeInterval = 8) {
        self.window = window
    }

    /// Records the total bytes received so far.
    public mutating func record(bytes: Int64, at date: Date = Date()) {
        let time = date.timeIntervalSinceReferenceDate
        // A lower count means the transfer started over; older samples no longer apply.
        if let last = samples.last, bytes < last.bytes || time < last.time {
            samples.removeAll()
        }
        samples.append(Sample(time: time, bytes: bytes))
        while samples.count > 2, let first = samples.first, first.time < time - window {
            samples.removeFirst()
        }
    }

    /// Recent average speed, or nil until there is enough history or while stalled.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time - first.time
        guard span >= minimumSpan, last.bytes > first.bytes else { return nil }
        return Double(last.bytes - first.bytes) / span
    }

    /// Seconds until `total` bytes are received at the current speed.
    public func secondsRemaining(until total: Int64) -> Double? {
        guard let rate = bytesPerSecond, let last = samples.last else { return nil }
        return Double(max(0, total - last.bytes)) / rate
    }
}

import Foundation

/// Works out the speed of each download from the progress reports that arrive
/// for it, and holds the readout steady enough to read.
public struct DownloadSpeedTracker: Sendable {
    /// Speed and time left for each download that is transferring.
    public private(set) var speeds: [String: DownloadSpeed] = [:]
    private var estimators: [String: TransferRateEstimator] = [:]
    private var publishedAt = Date.distantPast

    public init() {}

    /// Takes in the latest statuses, by recipe id.
    public mutating func update(from statuses: [String: DownloadStatus], at now: Date = Date()) {
        var latest: [String: DownloadSpeed] = [:]
        for (id, status) in statuses where status.state == .downloading {
            var estimator = estimators[id] ?? TransferRateEstimator()
            estimator.record(bytes: status.receivedBytes, at: now)
            estimators[id] = estimator
            if let rate = estimator.bytesPerSecond {
                latest[id] = DownloadSpeed(
                    bytesPerSecond: rate,
                    secondsRemaining: status.totalBytes.flatMap { estimator.secondsRemaining(until: $0) }
                )
            }
        }
        // A paused or finished transfer starts its estimate afresh next time.
        estimators = estimators.filter { latest[$0.key] != nil || statuses[$0.key]?.state == .downloading }
        // Progress arrives many times a second; a steadier readout is easier to read.
        if Set(latest.keys) != Set(speeds.keys) || now.timeIntervalSince(publishedAt) >= 1 {
            speeds = latest
            publishedAt = now
        }
    }
}

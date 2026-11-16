import Foundation
import Testing
@testable import KilnCore

@Suite struct DownloadSpeedTrackerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func downloading(_ received: Int64, of total: Int64? = 10_000) -> DownloadStatus {
        DownloadStatus(state: .downloading, receivedBytes: received, totalBytes: total, currentFile: nil)
    }

    /// A download that has moved 1,000 bytes a second for two seconds.
    private func running() -> DownloadSpeedTracker {
        var tracker = DownloadSpeedTracker()
        for second in 0...2 {
            tracker.update(from: ["a": downloading(Int64(second) * 1_000)], at: start.addingTimeInterval(Double(second)))
        }
        return tracker
    }

    @Test func aSpeedAppearsOnceThereIsEnoughToMeasure() {
        var tracker = DownloadSpeedTracker()
        tracker.update(from: ["a": downloading(0)], at: start)
        #expect(tracker.speeds.isEmpty)

        let speed = running().speeds["a"]
        #expect(speed?.bytesPerSecond == 1_000)
        #expect(speed?.secondsRemaining == 8)
    }

    @Test func withoutATotalThereIsNoTimeLeft() {
        var tracker = DownloadSpeedTracker()
        for second in 0...2 {
            tracker.update(from: ["a": downloading(Int64(second) * 1_000, of: nil)], at: start.addingTimeInterval(Double(second)))
        }
        #expect(tracker.speeds["a"]?.secondsRemaining == nil)
    }

    @Test func theReadoutChangesAtMostOnceASecond() {
        var tracker = running()
        tracker.update(from: ["a": downloading(9_000)], at: start.addingTimeInterval(2.2))
        #expect(tracker.speeds["a"]?.bytesPerSecond == 1_000)

        tracker.update(from: ["a": downloading(9_500)], at: start.addingTimeInterval(3.1))
        #expect((tracker.speeds["a"]?.bytesPerSecond ?? 0) > 1_000)
    }

    @Test func onlyDownloadsThatAreTransferringHaveASpeed() {
        var tracker = running()
        let paused = DownloadStatus(state: .paused, receivedBytes: 2_000, totalBytes: 10_000, currentFile: nil)
        tracker.update(from: ["a": paused], at: start.addingTimeInterval(2.1))
        // A download that stops is dropped at once, without waiting for the second to pass.
        #expect(tracker.speeds.isEmpty)
    }

    @Test func aResumedDownloadStartsItsEstimateAfresh() {
        var tracker = running()
        let paused = DownloadStatus(state: .paused, receivedBytes: 2_000, totalBytes: 10_000, currentFile: nil)
        tracker.update(from: ["a": paused], at: start.addingTimeInterval(3))
        tracker.update(from: ["a": downloading(2_000)], at: start.addingTimeInterval(60))
        #expect(tracker.speeds.isEmpty)
    }
}

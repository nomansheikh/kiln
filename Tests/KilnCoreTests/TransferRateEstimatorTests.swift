import Foundation
import Testing
@testable import KilnCore

@Suite struct TransferRateEstimatorTests {
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 1_000 + seconds)
    }

    @Test func needsSomeHistoryBeforeGivingASpeed() {
        var estimator = TransferRateEstimator()
        #expect(estimator.bytesPerSecond == nil)

        estimator.record(bytes: 0, at: date(0))
        estimator.record(bytes: 500, at: date(0.5))

        #expect(estimator.bytesPerSecond == nil)
        #expect(estimator.secondsRemaining(until: 10_000) == nil)
    }

    @Test func averagesSpeedAndPredictsTimeRemaining() {
        var estimator = TransferRateEstimator()
        estimator.record(bytes: 1_000, at: date(0))
        estimator.record(bytes: 3_000, at: date(1))
        estimator.record(bytes: 5_000, at: date(2))

        #expect(estimator.bytesPerSecond == 2_000)
        #expect(estimator.secondsRemaining(until: 15_000) == 5)
        #expect(estimator.secondsRemaining(until: 4_000) == 0)
    }

    @Test func followsRecentSpeedOnceOldSamplesLeaveTheWindow() {
        var estimator = TransferRateEstimator(window: 4)
        // 100 bytes/s for 10 seconds, then 1000 bytes/s.
        for second in 0...10 {
            estimator.record(bytes: Int64(second * 100), at: date(Double(second)))
        }
        for second in 11...16 {
            estimator.record(bytes: Int64(1_000 + (second - 10) * 1_000), at: date(Double(second)))
        }

        #expect(estimator.bytesPerSecond == 1_000)
    }

    @Test func aStalledTransferHasNoSpeed() {
        var estimator = TransferRateEstimator()
        estimator.record(bytes: 5_000, at: date(0))
        estimator.record(bytes: 5_000, at: date(3))

        #expect(estimator.bytesPerSecond == nil)
        #expect(estimator.secondsRemaining(until: 10_000) == nil)
    }

    @Test func startingOverDiscardsEarlierSamples() {
        var estimator = TransferRateEstimator()
        estimator.record(bytes: 0, at: date(0))
        estimator.record(bytes: 9_000, at: date(3))

        estimator.record(bytes: 100, at: date(4))
        #expect(estimator.bytesPerSecond == nil)

        estimator.record(bytes: 700, at: date(6))
        #expect(estimator.bytesPerSecond == 300)
    }
}

import Foundation
import Testing
@testable import KilnCore

/// The wording depends on the Mac's language, so only its shape is checked.
@Suite struct DownloadSpeedTests {
    @Test func theSpeedIsGivenPerSecond() {
        let speed = DownloadSpeed(bytesPerSecond: 12_400_000, secondsRemaining: nil)
        #expect(speed.speedText.hasSuffix("/s"))
        #expect(speed.speedText.contains("12"))
    }

    @Test func withoutAnEstimateOnlyTheSpeedIsShown() {
        let speed = DownloadSpeed(bytesPerSecond: 1_000, secondsRemaining: nil)
        #expect(speed.remainingText == nil)
        #expect(speed.shortRemainingText == nil)
        #expect(speed.summary == speed.speedText)
    }

    @Test func theLastSecondsAreNotCounted() {
        let speed = DownloadSpeed(bytesPerSecond: 1_000, secondsRemaining: 4.9)
        #expect(speed.remainingText == "A few seconds left")
        #expect(speed.shortRemainingText == "a few sec left")
    }

    @Test func theTimeLeftIsRoundedToOneUnit() {
        let speed = DownloadSpeed(bytesPerSecond: 1_000, secondsRemaining: 8 * 60 + 20)
        let text = speed.remainingText ?? ""
        #expect(text.hasPrefix("About 8") && text.hasSuffix(" left"))
        #expect(!text.contains("20"))
        #expect(speed.shortRemainingText?.hasPrefix("8") == true)
        #expect(speed.summary == "\(speed.speedText) · \(text)")
    }
}

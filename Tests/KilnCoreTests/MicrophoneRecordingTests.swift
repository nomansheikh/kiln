import Foundation
import Testing
@testable import KilnCore

@Suite struct MicrophoneRecordingTests {
    @Test func aRecordingIsNamedAfterTheMomentItStarted() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let date = Date(timeIntervalSince1970: 1_795_545_730)
        #expect(MicrophoneRecording.fileName(at: date, timeZone: utc) == "Recording 2026-11-24 at 18.42.10.m4a")
    }

    @Test func aRecordingsNameCountsAsAudio() {
        let name = MicrophoneRecording.fileName(at: Date())
        #expect(AttachmentLibrary.kind(of: URL(fileURLWithPath: "/tmp/\(name)")) == .audio)
        #expect(!name.contains(":") && !name.contains("/"))
    }

    @Test func aLevelIsAShareOfFullHeight() {
        #expect(MicrophoneRecording.level(decibels: 0) == 1)
        #expect(MicrophoneRecording.level(decibels: -25) == 0.5)
        #expect(MicrophoneRecording.level(decibels: -50) == 0)
        #expect(MicrophoneRecording.level(decibels: -160) == 0)
        #expect(MicrophoneRecording.level(decibels: 6) == 1)
        #expect(MicrophoneRecording.level(decibels: -.infinity) == 0)
        #expect(MicrophoneRecording.level(decibels: .nan) == 0)
    }
}

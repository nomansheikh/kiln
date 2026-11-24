import Foundation

/// The rules of a recording made with the microphone: what its file is called and how loud a moment looks.
public enum MicrophoneRecording {
    /// `Recording 2026-11-24 at 18.42.10.m4a`: sorts by time and has no character a file name may not hold.
    public static func fileName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recording \(formatter.string(from: date)).m4a"
    }

    /// A level meter's reading as a share of full height. Anything quieter than
    /// `floor` decibels shows as silence; 0 decibels is as loud as the input gets.
    public static func level(decibels: Float, floor: Float = -50) -> Double {
        guard decibels.isFinite, decibels > floor else { return 0 }
        return Double(min((decibels - floor) / -floor, 1))
    }
}

import Foundation

/// A transcript as a subtitle file.
extension Transcript {
    public enum SubtitleFormat: String, Sendable, CaseIterable {
        case srt
        case vtt

        public var name: String {
            switch self {
            case .srt: "SubRip (.srt)"
            case .vtt: "WebVTT (.vtt)"
            }
        }
    }

    public func subtitles(_ format: SubtitleFormat) -> String {
        switch format {
        case .srt:
            // SubRip numbers its cues from one and writes the fraction after a comma.
            return segments.enumerated().map { index, segment in
                "\(index + 1)\n\(Self.stamp(segment.start, fraction: ",")) --> \(Self.stamp(segment.end, fraction: ","))\n\(segment.text)\n"
            }.joined(separator: "\n")
        case .vtt:
            return "WEBVTT\n\n" + segments.map { segment in
                "\(Self.stamp(segment.start, fraction: ".")) --> \(Self.stamp(segment.end, fraction: "."))\n\(segment.text)\n"
            }.joined(separator: "\n")
        }
    }

    /// `00:01:02,500`: both formats want every field, down to the millisecond.
    private static func stamp(_ seconds: TimeInterval, fraction: String) -> String {
        let milliseconds = Int((max(seconds, 0) * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d\(fraction)%03d",
            milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000
        )
    }
}

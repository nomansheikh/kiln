import Foundation

/// What was said in a recording: stretches of speech, each with the time it starts and ends at.
public struct Transcript: Sendable, Hashable, Codable {
    public struct Segment: Sendable, Hashable, Codable {
        /// Seconds from the start of the recording.
        public var start: TimeInterval
        public var end: TimeInterval
        public var text: String

        public init(start: TimeInterval, end: TimeInterval, text: String) {
            self.start = start
            self.end = end
            self.text = text
        }
    }

    public var segments: [Segment]

    /// Segments without words are left out, and the rest lose the space a model puts before each.
    public init(segments: [Segment]) {
        self.segments = segments.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : Segment(start: segment.start, end: max(segment.end, segment.start), text: text)
        }
    }

    /// Adds a stretch of speech as it arrives, by the same rules as a whole transcript.
    public mutating func append(_ segment: Segment) {
        segments += Transcript(segments: [segment]).segments
    }

    /// Whether a pause before this segment is long enough to read as a new paragraph.
    public func startsParagraph(at index: Int, pause: TimeInterval = 2) -> Bool {
        index > 0 && segments.indices.contains(index) && segments[index].start - segments[index - 1].end >= pause
    }

    /// The time the last segment ends at: the length of the recording, near enough.
    public var duration: TimeInterval { segments.last?.end ?? 0 }

    /// Everything that was said, as one paragraph.
    public var text: String {
        segments.map(\.text).joined(separator: " ")
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// Whether times are worth showing: a transcript of one segment has only the length of the recording.
    public var hasTimes: Bool { segments.count > 1 }

    /// The segment being spoken at a time in the recording: the last one that has started by then.
    /// Nil before the first one starts.
    public func segmentIndex(at seconds: TimeInterval) -> Int? {
        segments.lastIndex { $0.start <= seconds }
    }

    /// A time as a person reads it on a player: `0:07`, `12:30`, `1:02:03`.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0))
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

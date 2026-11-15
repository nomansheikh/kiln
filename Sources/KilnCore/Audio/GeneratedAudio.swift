import Foundation

/// Sound a model produced: 32-bit float samples, interleaved by channel.
public struct GeneratedAudio: Sendable, Hashable {
    public var sampleRate: Int
    public var channels: Int
    /// Raw little-endian floats, `channels` per frame.
    public var samples: Data

    public init(sampleRate: Int, channels: Int, samples: Data) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.samples = samples
    }

    public var frameCount: Int {
        channels > 0 ? samples.count / (MemoryLayout<Float32>.size * channels) : 0
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / Double(sampleRate) : 0
    }

    /// Several sounds one after another, with a pause between them. Nil when
    /// there are none or they differ in sample rate or channels.
    public static func joined(_ parts: [GeneratedAudio], gapSeconds: Double = 0.25) -> GeneratedAudio? {
        guard let first = parts.first,
              parts.allSatisfy({ $0.sampleRate == first.sampleRate && $0.channels == first.channels })
        else { return nil }
        let gap = Data(count: Int(Double(first.sampleRate) * gapSeconds) * first.channels * MemoryLayout<Float32>.size)
        var samples = Data()
        for (index, part) in parts.enumerated() {
            if index > 0 { samples.append(gap) }
            samples.append(part.samples)
        }
        return GeneratedAudio(sampleRate: first.sampleRate, channels: first.channels, samples: samples)
    }

    /// The sound as a 16-bit PCM WAV file, which every player opens.
    public func wavData() throws(AudioCodecError) -> Data {
        guard sampleRate > 0, (1...2).contains(channels), frameCount > 0,
              samples.count == frameCount * channels * MemoryLayout<Float32>.size
        else {
            throw .invalidSamples
        }
        let sampleCount = frameCount * channels
        let dataSize = sampleCount * MemoryLayout<Int16>.size
        var wav = Data(capacity: 44 + dataSize)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
        }
        wav.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        wav.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))                       // size of the format block
        append(UInt16(1))                        // PCM
        append(UInt16(channels))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * channels * 2)) // bytes per second
        append(UInt16(channels * 2))             // bytes per frame
        append(UInt16(16))                       // bits per sample
        wav.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        samples.withUnsafeBytes { raw in
            for index in 0..<sampleCount {
                let sample = raw.loadUnaligned(fromByteOffset: index * MemoryLayout<Float32>.size, as: Float32.self)
                // Out-of-range and non-finite samples are clipped rather than wrapped.
                let clipped = sample.isFinite ? max(-1, min(1, sample)) : 0
                append(Int16((clipped * Float32(Int16.max)).rounded()))
            }
        }
        return wav
    }
}

public enum AudioCodecError: Error, Equatable, LocalizedError {
    case invalidSamples

    public var errorDescription: String? {
        "The audio data is not valid."
    }
}

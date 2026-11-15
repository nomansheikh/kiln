import Foundation

/// The outline of a sound, for drawing it.
public enum AudioWaveform {
    /// How loud a 16-bit PCM WAV file is over time, as `count` values from 0 to 1.
    ///
    /// Each value is the loudest sample in its slice of the file, scaled so the
    /// loudest slice is 1: a quiet recording still draws a full-height shape.
    /// Returns an empty array for a file that is not such a WAV.
    public static func peaks(of file: URL, count: Int) -> [Float] {
        guard count > 0, let data = try? Data(contentsOf: file, options: .mappedIfSafe),
              let samples = pcmSamples(in: data)
        else { return [] }

        let total = samples.count / MemoryLayout<Int16>.size
        guard total > 0 else { return [] }
        var peaks = [Float](repeating: 0, count: count)
        samples.withUnsafeBytes { raw in
            for bucket in 0..<count {
                let start = bucket * total / count
                let end = max(start + 1, (bucket + 1) * total / count)
                var loudest: Int32 = 0
                // A long file has far more samples than pixels; a sparse scan is enough.
                let stride = max(1, (end - start) / 256)
                var index = start
                while index < min(end, total) {
                    let sample = Int32(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self)))
                    loudest = max(loudest, abs(sample))
                    index += stride
                }
                peaks[bucket] = Float(loudest) / Float(Int16.max)
            }
        }
        guard let loudest = peaks.max(), loudest > 0 else { return peaks }
        return peaks.map { min(1, $0 / loudest) }
    }

    /// The sample bytes of a 16-bit PCM WAV, found by walking its chunks.
    private static func pcmSamples(in data: Data) -> Data? {
        func text(_ offset: Int) -> String { String(decoding: data[data.startIndex + offset..<data.startIndex + offset + 4], as: UTF8.self) }
        func number<T: FixedWidthInteger>(_ offset: Int, as type: T.Type) -> T {
            data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
        }
        guard data.count >= 12, text(0) == "RIFF", text(8) == "WAVE" else { return nil }
        var offset = 12
        var isPCM16 = false
        while offset + 8 <= data.count {
            let size = Int(number(offset + 4, as: UInt32.self))
            let body = offset + 8
            guard size >= 0, body + size <= data.count || text(offset) == "data" else { return nil }
            switch text(offset) {
            case "fmt ":
                guard size >= 16 else { return nil }
                isPCM16 = number(body, as: UInt16.self) == 1 && number(body + 14, as: UInt16.self) == 16
            case "data":
                guard isPCM16 else { return nil }
                let end = min(body + size, data.count)
                return data.subdata(in: data.startIndex + body..<data.startIndex + end)
            default:
                break
            }
            // Chunks are padded to an even length.
            offset = body + size + (size % 2)
        }
        return nil
    }
}

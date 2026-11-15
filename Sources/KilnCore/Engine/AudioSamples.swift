import AVFoundation

/// Decodes audio files into the samples speech models read.
public enum AudioSamples {
    /// The sample rate whisper.cpp expects.
    public static let sampleRate: Double = 16_000

    /// Decodes an audio file to mono 32-bit float samples at 16 kHz.
    public static func decode(_ file: URL) throws(EngineError) -> [Float] {
        do {
            let source = try AVAudioFile(forReading: file)
            guard source.length > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: source.processingFormat, to: format),
                  let input = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 1 << 16),
                  let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16)
            else {
                throw EngineError.unreadableAudio
            }

            var samples: [Float] = []
            samples.reserveCapacity(Int(Double(source.length) * sampleRate / source.processingFormat.sampleRate))
            var failed = false
            var status = AVAudioConverterOutputStatus.haveData
            while status == .haveData {
                var conversionError: NSError?
                status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
                    // Reading at the end of the file is an error on some systems, so stop before it.
                    guard !failed, source.framePosition < source.length else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    do {
                        try source.read(into: input)
                    } catch {
                        failed = true
                    }
                    guard !failed, input.frameLength > 0 else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return input
                }
                guard !failed, status != .error, conversionError == nil else { throw EngineError.unreadableAudio }
                if let channel = output.floatChannelData?[0], output.frameLength > 0 {
                    samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
                }
            }
            guard !samples.isEmpty else { throw EngineError.unreadableAudio }
            return samples
        } catch {
            throw .unreadableAudio
        }
    }

    /// Writes the decoded samples as raw little-endian floats, where a helper reads them.
    static func write(_ file: URL, to destination: URL) throws(EngineError) {
        let samples = try decode(file)
        do {
            try samples.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: destination)
        } catch {
            throw .unreadableAudio
        }
    }
}

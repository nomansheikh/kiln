import Foundation

extension FileHandle {
    /// Lines written to a pipe, delivered as soon as each one is complete.
    var lines: AsyncStream<String> {
        AsyncStream { continuation in
            // The handler runs on one serial queue per handle, so the buffer needs no lock.
            nonisolated(unsafe) var buffer = Data()
            readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else {
                    handle.readabilityHandler = nil
                    if !buffer.isEmpty {
                        continuation.yield(String(decoding: buffer, as: UTF8.self))
                    }
                    continuation.finish()
                    return
                }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    continuation.yield(String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self))
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
            }
        }
    }
}

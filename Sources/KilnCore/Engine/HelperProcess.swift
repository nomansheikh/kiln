import Foundation

/// A running `kiln-engine` helper with its pipes.
struct HelperProcess {
    let process: Process
    /// Where requests are written.
    let input: FileHandle
    /// Protocol lines from the helper's stdout.
    let events: AsyncStream<String>
    /// Log lines from the helper's stderr.
    let logs: AsyncStream<String>

    static func launch(_ executable: URL) throws(EngineError) -> HelperProcess {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw .helperUnavailable("kiln-engine is missing from the app.")
        }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw .helperUnavailable(error.localizedDescription)
        }
        return HelperProcess(
            process: process,
            input: stdin.fileHandleForWriting,
            events: stdout.fileHandleForReading.lines,
            logs: stderr.fileHandleForReading.lines
        )
    }
}

extension GeneratedImage {
    /// Reads raw pixels the helper wrote, or nil when the file does not match the stated size.
    init?(rawFile path: String, width: Int, height: Int, channels: Int) {
        guard width > 0, height > 0, [1, 3, 4].contains(channels),
              let pixels = try? Data(contentsOf: URL(fileURLWithPath: path)), pixels.count == width * height * channels
        else { return nil }
        self.init(width: width, height: height, channels: channels, pixels: pixels)
    }
}

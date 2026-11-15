import Foundation

/// A running helper, such as `kiln-engine`, with its pipes.
struct HelperProcess {
    let process: Process
    /// Where requests are written.
    let input: FileHandle
    /// Protocol lines from the helper's stdout.
    let events: AsyncStream<String>
    /// Log lines from the helper's stderr.
    let logs: AsyncStream<String>

    /// The only variables a helper is started with. A helper reads files from the
    /// internet, so it is not handed the app's whole environment, which can hold
    /// access tokens such as `HF_TOKEN`.
    static let passedVariables: Set<String> = ["HOME", "TMPDIR", "USER", "LOGNAME", "LANG"]

    /// What a helper is started with, out of the app's own environment.
    static func environment(from parent: [String: String]) -> [String: String] {
        var environment = parent.filter { passedVariables.contains($0.key) }
        environment["PATH"] = "/usr/bin:/bin"
        return environment
    }

    /// The arguments that make a helper confine itself (see `Engine/sandbox.h`):
    /// it may then read the models folder, write the scratch folder, and reach
    /// neither the network nor the rest of the user's files.
    static func sandboxArguments(models: URL, scratch: URL) -> [String] {
        ["--sandbox", models.path, scratch.path]
    }

    static func launch(_ executable: URL, arguments: [String] = []) throws(EngineError) -> HelperProcess {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw .helperUnavailable("\(executable.lastPathComponent) is missing from the app.")
        }
        let process = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment(from: ProcessInfo.processInfo.environment)
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

extension GenerationRequest {
    /// Writes the attached image as raw RGB at the output size, where the helper reads it.
    /// Returns nil when the request has no attachment or is not for an image.
    func writeSourceImage(to file: URL) throws(EngineError) -> URL? {
        guard let attachment, let settings = image else { return nil }
        do {
            try ImageCodec.rgbPixels(of: attachment, width: settings.width, height: settings.height).write(to: file)
        } catch {
            throw .unreadableSourceImage
        }
        return file
    }
}

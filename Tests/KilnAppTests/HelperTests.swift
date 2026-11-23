import Foundation
import Testing

/// The four built helpers, started for real but without a model: how each
/// starts, what it answers to a request it cannot read, and how it ends. The
/// app build, which runs before these tests, makes the helpers when they are missing.
@Suite struct HelperTests {
    static let helpers = ["engine/kiln-engine", "whisper/kiln-whisper", "audio/kiln-audio", "trellis/kiln-trellis"]

    /// `build/` at the repository root.
    private static let buildDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("build")

    private static func isBuilt(_ helper: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: buildDirectory.appendingPathComponent(helper).path)
    }

    private struct Run {
        let events: [[String: String]]
        let log: String
        let status: Int32
    }

    /// Starts a helper, sends it the lines, closes its input and collects what it said.
    private func run(_ helper: String, arguments: [String], lines: [String] = []) throws -> Run {
        let process = Process()
        process.executableURL = Self.buildDirectory.appendingPathComponent(helper)
        process.arguments = arguments
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // A helper that never ends must not hang the tests.
        let watchdog = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)
        defer { watchdog.cancel() }

        try input.fileHandleForWriting.write(contentsOf: Data(lines.map { $0 + "\n" }.joined().utf8))
        try input.fileHandleForWriting.close()
        let said = try output.fileHandleForReading.readToEnd() ?? Data()
        let logged = try errors.fileHandleForReading.readToEnd() ?? Data()
        process.waitUntilExit()

        let events = String(decoding: said, as: UTF8.self).split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?.compactMapValues { $0 as? String }
        }
        return Run(events: events, log: String(decoding: logged, as: UTF8.self), status: process.terminationStatus)
    }

    private func sandbox() throws -> [String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-helper-tests-\(UUID().uuidString)")
        let folders = ["models", "scratch"].map { root.appendingPathComponent($0) }
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return ["--sandbox"] + folders.map(\.path)
    }

    @Test(arguments: helpers)
    func aHelperSaysItIsReadyInsideItsSandboxAndEndsWithItsInput(_ helper: String) throws {
        try #require(Self.isBuilt(helper), "build/\(helper) is not built")
        let run = try run(helper, arguments: try sandbox())

        #expect(run.events.map { $0["type"] } == ["ready"])
        #expect(run.events.first?["version"]?.isEmpty == false)
        #expect(run.status == 0)
    }

    @Test(arguments: helpers)
    func aRequestItCannotReadIsAnsweredAndDoesNotStopIt(_ helper: String) throws {
        try #require(Self.isBuilt(helper), "build/\(helper) is not built")
        let run = try run(helper, arguments: try sandbox(), lines: ["not json", #"{"type":"dance"}"#, "[1]"])

        #expect(run.events.map { $0["type"] } == ["ready", "error", "error", "error"])
        #expect(run.events.dropFirst().allSatisfy { $0["code"] == "invalid_request" })
        #expect(run.events[safe: 2]?["message"] == "Unknown request type \"dance\".")
        #expect(run.status == 0)
    }

    @Test(arguments: helpers)
    func aHelperRefusesToRunWithHalfASandbox(_ helper: String) throws {
        try #require(Self.isBuilt(helper), "build/\(helper) is not built")
        let run = try run(helper, arguments: ["--sandbox", "/tmp"])

        #expect(run.events.isEmpty)
        #expect(run.status == 1)
        #expect(run.log.contains("could not enter the sandbox"))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

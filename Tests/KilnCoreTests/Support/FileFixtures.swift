import Foundation
@testable import KilnCore

/// A folder of its own for a test, with files of the kinds Kiln takes.
struct FileFixtures {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-file-tests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A real PNG, two pixels wide.
    func image(named name: String = "picture.png") throws -> URL {
        let image = GeneratedImage(width: 2, height: 1, channels: 3, pixels: Data(repeating: 128, count: 6))
        let record = GenerationRecord(recipeID: "r", recipeName: "R", request: GenerationRequest(prompt: "p"), durationSeconds: nil)
        return try write(ImageCodec.pngData(for: image, record: record), named: name)
    }

    /// A file that is only what its name says it is.
    func file(named name: String) throws -> URL {
        try write(Data("contents".utf8), named: name)
    }

    private func write(_ data: Data, named name: String) throws -> URL {
        let file = root.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}

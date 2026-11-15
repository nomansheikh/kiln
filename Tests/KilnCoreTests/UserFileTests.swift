import Foundation
import Testing
@testable import KilnCore

@Suite struct UserFileTests {
    private func file() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-user-file-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("clip.wav")
        try Data("sound".utf8).write(to: file)
        return file
    }

    @Test func aDiscardedFileGoesToTheTrashAndCanBeFoundThere() throws {
        let file = try file()
        let moved = try #require(try UserFile.discard(file))
        // Tidy up whatever happens, so the test leaves nothing in the user's Trash.
        defer { try? FileManager.default.removeItem(at: moved) }
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: moved) == Data("sound".utf8))
    }

    @Test func aFileCanBeErasedOutright() throws {
        let file = try file()
        #expect(try UserFile.discard(file, permanently: true) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func discardingAMissingFileIsAnError() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("kiln-missing-\(UUID().uuidString).wav")
        #expect(throws: (any Error).self) { try UserFile.discard(missing) }
    }
}

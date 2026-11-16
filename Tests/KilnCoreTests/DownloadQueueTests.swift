import Foundation
import Testing
@testable import KilnCore

/// What happens to downloads that are waiting or done: pausing, forgetting and the disk check.
@Suite struct DownloadQueueTests {
    private let storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-dq-\(UUID().uuidString)"))
    private let downloader = FakeDownloader()

    private func recipe(_ id: String) -> ModelRecipe {
        makeRecipe(id: id, components: [
            .init(role: .checkpoint, repo: "owner/\(id)", file: "\(id).safetensors", revision: "abc", sizeBytes: 100,
                  sha256: String(repeating: "ab", count: 32)),
        ])
    }

    private func waitFor(
        _ manager: DownloadManager, _ id: String, _ condition: @escaping @Sendable (DownloadStatus?) -> Bool
    ) async {
        for await statuses in await manager.updates() where condition(statuses[id]) { return }
    }

    @Test func aFinishedEntryCanBeForgottenButARunningOneCannot() async {
        downloader.block("second.safetensors")
        let manager = DownloadManager(storage: storage, downloader: downloader, freeSpace: { _ in nil })
        await manager.start(recipe("first"))
        await manager.start(recipe("second"))
        await waitFor(manager, "second") { $0?.state == .downloading }

        await manager.clear("first")
        await manager.clear("second")

        #expect(await manager.allStatuses().keys.sorted() == ["second"])
        downloader.release("second.safetensors")
        await waitFor(manager, "second") { $0?.state == .completed }
    }

    @Test func aWaitingDownloadCanBePausedAndIsThenSkipped() async {
        downloader.block("first.safetensors")
        let manager = DownloadManager(storage: storage, downloader: downloader, freeSpace: { _ in nil })
        await manager.start(recipe("first"))
        await manager.start(recipe("second"))
        await waitFor(manager, "first") { $0?.state == .downloading }

        await manager.pause("second")
        // Pausing something that is not downloading changes nothing.
        await manager.pause("unknown")
        downloader.release("first.safetensors")
        await waitFor(manager, "first") { $0?.state == .completed }

        #expect(await manager.status(for: "second")?.state == .paused)
        #expect(downloader.startedFiles == ["first.safetensors"])
    }

    @Test func aFailureIsShownInTheErrorsOwnWords() async {
        downloader.fail("first.safetensors", with: .checksumMismatch)
        let manager = DownloadManager(storage: storage, downloader: downloader, freeSpace: { _ in nil })
        await manager.start(recipe("first"))
        await waitFor(manager, "first") { if case .failed = $0?.state { true } else { false } }

        #expect(await manager.status(for: "first")?.state == .failed(DownloadError.checksumMismatch.errorDescription ?? ""))
    }

    @Test func freeSpaceIsReadFromTheVolumeOfAFolderThatDoesNotExistYet() throws {
        let missing = storage.root.appendingPathComponent("a/b/c")
        let available = try #require(DownloadManager.volumeFreeSpace(missing))
        #expect(available > 0)
    }
}

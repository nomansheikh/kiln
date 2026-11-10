import Foundation
import Testing
@testable import KilnCore

/// Writes files instantly, or blocks until released so tests can observe mid-download states.
final class FakeDownloader: FileDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var started: [String] = []
    private var failures: [String: DownloadError] = [:]
    private var blocked: Set<String> = []

    var startedFiles: [String] { lock.withLock { started } }

    func block(_ name: String) { lock.withLock { _ = blocked.insert(name) } }
    func fail(_ name: String, with error: DownloadError) { lock.withLock { failures[name] = error } }
    func succeedFromNowOn(_ name: String) { lock.withLock { failures[name] = nil } }

    func release(_ name: String) {
        lock.withLock {
            blocked.remove(name)
            return gates.removeValue(forKey: name)
        }?.resume()
    }

    func download(_ item: DownloadItem, onEvent: @escaping @Sendable (TransferEvent) -> Void) async throws {
        let name = item.destination.lastPathComponent
        let size = item.expectedSize ?? 10
        lock.withLock { started.append(name) }
        onEvent(.progress(receivedBytes: size / 2, totalBytes: size))

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let wait = lock.withLock {
                    guard blocked.contains(name), !Task.isCancelled else { return false }
                    gates[name] = continuation
                    return true
                }
                if !wait { continuation.resume() }
            }
        } onCancel: {
            lock.withLock { gates.removeValue(forKey: name) }?.resume()
        }
        try Task.checkCancellation()
        if let failure = lock.withLock({ failures[name] }) { throw failure }

        onEvent(.verifying)
        try FileManager.default.createDirectory(at: item.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: Int(size)).write(to: item.destination)
    }
}

@Suite struct DownloadManagerTests {
    let storage: ModelStorage
    let downloader = FakeDownloader()

    init() {
        storage = ModelStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-dm-\(UUID().uuidString)"))
    }

    private func manager(freeSpace: Int64? = 1_000_000) -> DownloadManager {
        DownloadManager(storage: storage, downloader: downloader, freeSpace: { _ in freeSpace })
    }

    private func recipe(_ id: String = "model", files: [String] = ["llm.gguf", "vae.safetensors"]) -> ModelRecipe {
        let roles: [ModelRecipe.ComponentRole] = [.llm, .vae, .diffusionModel, .checkpoint]
        return makeRecipe(id: id, components: files.enumerated().map { index, file in
            .init(role: roles[index], repo: "owner/\(id)", file: file, revision: "abc", sizeBytes: 100)
        })
    }

    /// Waits until the recipe's status satisfies `condition`.
    private func waitFor(
        _ manager: DownloadManager,
        _ id: String = "model",
        _ condition: @escaping @Sendable (DownloadStatus?) -> Bool
    ) async -> DownloadStatus? {
        for await statuses in await manager.updates() where condition(statuses[id]) {
            return statuses[id]
        }
        return nil
    }

    @Test func downloadsEveryComponentThenCompletes() async throws {
        let manager = manager()
        await manager.start(recipe())

        let status = await waitFor(manager) { $0?.state == .completed }

        #expect(status?.receivedBytes == 200)
        #expect(status?.totalBytes == 200)
        #expect(status?.fraction == 1)
        #expect(downloader.startedFiles == ["llm.gguf", "vae.safetensors"])
        #expect(storage.isInstalled(recipe()))
    }

    @Test func skipsComponentsThatAreAlreadyInstalled() async throws {
        let model = recipe()
        let existing = storage.url(for: model.components[0])
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 100).write(to: existing)
        let manager = manager()

        await manager.start(model)
        _ = await waitFor(manager) { $0?.state == .completed }

        #expect(downloader.startedFiles == ["vae.safetensors"])
    }

    @Test func reportsProgressAcrossFiles() async throws {
        downloader.block("vae.safetensors")
        let manager = manager()
        await manager.start(recipe())

        // First file finished (100) plus half of the second (50).
        let status = await waitFor(manager) { $0?.receivedBytes == 150 }
        #expect(status?.state == .downloading)
        #expect(status?.currentFile == "vae.safetensors")
        #expect(status?.fraction == 0.75)

        downloader.release("vae.safetensors")
        _ = await waitFor(manager) { $0?.state == .completed }
    }

    @Test func pauseKeepsTheEntryAndStartContinuesIt() async throws {
        downloader.block("llm.gguf")
        let manager = manager()
        await manager.start(recipe())
        _ = await waitFor(manager) { $0?.state == .downloading }

        await manager.pause("model")
        #expect(await manager.status(for: "model")?.state == .paused)
        #expect(!storage.isInstalled(recipe()))

        downloader.release("llm.gguf")
        await manager.start(recipe())
        let status = await waitFor(manager) { $0?.state == .completed }

        #expect(status?.state == .completed)
        #expect(storage.isInstalled(recipe()))
    }

    @Test func cancelRemovesTheEntryAndPartialFiles() async throws {
        let model = recipe()
        let partial = FileDownloader.partialURL(for: storage.url(for: model.components[0]))
        try FileManager.default.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 40).write(to: partial)
        downloader.block("llm.gguf")
        let manager = manager()
        await manager.start(model)
        _ = await waitFor(manager) { $0?.state == .downloading }

        await manager.cancel("model")

        #expect(await manager.status(for: "model") == nil)
        #expect(!FileManager.default.fileExists(atPath: partial.path))
    }

    @Test func startingTwiceDoesNotDownloadTwice() async throws {
        downloader.block("llm.gguf")
        let manager = manager()
        await manager.start(recipe())
        await manager.start(recipe())
        _ = await waitFor(manager) { $0?.state == .downloading }

        downloader.release("llm.gguf")
        _ = await waitFor(manager) { $0?.state == .completed }

        #expect(downloader.startedFiles == ["llm.gguf", "vae.safetensors"])
    }

    @Test func runsOneRecipeAtATimeInOrder() async throws {
        downloader.block("a.gguf")
        let manager = manager()
        await manager.start(recipe("first", files: ["a.gguf"]))
        await manager.start(recipe("second", files: ["b.gguf"]))
        _ = await waitFor(manager, "first") { $0?.state == .downloading }

        #expect(await manager.status(for: "second")?.state == .queued)
        #expect(downloader.startedFiles == ["a.gguf"])

        downloader.release("a.gguf")
        _ = await waitFor(manager, "second") { $0?.state == .completed }
        #expect(downloader.startedFiles == ["a.gguf", "b.gguf"])
    }

    @Test func failsBeforeDownloadingWhenTheDiskIsTooFull() async throws {
        let manager = manager(freeSpace: 150)
        await manager.start(recipe())

        let status = await waitFor(manager) { if case .failed = $0?.state { true } else { false } }

        #expect(status?.state == .failed(DownloadError.notEnoughDiskSpace(needed: 200, available: 150).errorDescription!))
        #expect(downloader.startedFiles.isEmpty)
    }

    @Test func diskCheckOnlyCountsWhatIsStillMissing() async throws {
        let model = recipe()
        let existing = storage.url(for: model.components[0])
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 100).write(to: existing)
        let partial = FileDownloader.partialURL(for: storage.url(for: model.components[1]))
        try Data(count: 60).write(to: partial)

        // 40 bytes are still needed, so 50 free is enough.
        let manager = manager(freeSpace: 50)
        await manager.start(model)
        let status = await waitFor(manager) { $0?.state == .completed }

        #expect(status?.state == .completed)
    }

    @Test func aFailedDownloadCanBeRetried() async throws {
        downloader.fail("llm.gguf", with: .checksumMismatch)
        let manager = manager()
        await manager.start(recipe())
        let failed = await waitFor(manager) { if case .failed = $0?.state { true } else { false } }
        #expect(failed?.state == .failed(DownloadError.checksumMismatch.errorDescription!))

        downloader.succeedFromNowOn("llm.gguf")
        await manager.start(recipe())
        let status = await waitFor(manager) { $0?.state == .completed }

        #expect(status?.state == .completed)
    }

    @Test func deletingARecipeKeepsFilesSharedWithAnotherRecipe() async throws {
        let shared = ModelRecipe.Component(role: .vae, repo: "owner/shared", file: "vae.safetensors", sizeBytes: 100)
        let first = makeRecipe(id: "first", components: [.init(role: .checkpoint, repo: "owner/first", file: "a.gguf", sizeBytes: 100), shared])
        let second = makeRecipe(id: "second", components: [.init(role: .checkpoint, repo: "owner/second", file: "b.gguf", sizeBytes: 100), shared])
        let manager = manager()
        await manager.start(first)
        await manager.start(second)
        _ = await waitFor(manager, "second") { $0?.state == .completed }

        try storage.delete(first, keeping: [first, second])

        #expect(!storage.isInstalled(first))
        #expect(storage.isInstalled(second))
        #expect(!FileManager.default.fileExists(atPath: storage.root.appendingPathComponent("owner/first").path))

        try storage.delete(second, keeping: [second])
        #expect(!storage.isInstalled(shared))
    }
}

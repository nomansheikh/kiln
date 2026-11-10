import Foundation

public struct DownloadStatus: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case queued
        case downloading
        case verifying
        case paused
        case completed
        case failed(String)
    }

    public var state: State
    public var receivedBytes: Int64
    public var totalBytes: Int64?
    /// Name of the file being transferred.
    public var currentFile: String?

    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(receivedBytes) / Double(totalBytes))
    }

    public var isActive: Bool {
        state == .queued || state == .downloading || state == .verifying
    }
}

/// Downloads every missing component of a recipe, one recipe at a time.
public actor DownloadManager {
    public typealias FreeSpaceProbe = @Sendable (URL) -> Int64?

    private let storage: ModelStorage
    private let downloader: any FileDownloading
    private let freeSpace: FreeSpaceProbe

    private var recipes: [String: ModelRecipe] = [:]
    private var statuses: [String: DownloadStatus] = [:]
    private var queue: [String] = []
    private var active: (id: String, task: Task<Void, Never>)?
    private var observers: [UUID: AsyncStream<[String: DownloadStatus]>.Continuation] = [:]

    public init(
        storage: ModelStorage,
        downloader: any FileDownloading,
        freeSpace: @escaping FreeSpaceProbe = DownloadManager.volumeFreeSpace
    ) {
        self.storage = storage
        self.downloader = downloader
        self.freeSpace = freeSpace
    }

    public static let volumeFreeSpace: FreeSpaceProbe = { directory in
        // The directory may not exist yet, so ask about its closest existing parent.
        var probe = directory
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        return try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    public func status(for id: String) -> DownloadStatus? {
        statuses[id]
    }

    public func allStatuses() -> [String: DownloadStatus] {
        statuses
    }

    /// Emits the full status table now and after every change.
    public func updates() -> AsyncStream<[String: DownloadStatus]> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: [String: DownloadStatus].self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let token = UUID()
        observers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(token) }
        }
        continuation.yield(statuses)
        return stream
    }

    /// Queues a recipe, or continues it when it was paused or failed.
    public func start(_ recipe: ModelRecipe) {
        if let status = statuses[recipe.id], status.isActive { return }
        recipes[recipe.id] = recipe
        update(recipe.id) { status in
            status.state = .queued
            status.totalBytes = recipe.totalSizeBytes
            status.receivedBytes = self.bytesOnDisk(for: recipe)
        }
        queue.append(recipe.id)
        runNextIfIdle()
    }

    /// Stops the transfer and keeps what was downloaded so far.
    public func pause(_ id: String) {
        guard let status = statuses[id], status.isActive else { return }
        queue.removeAll { $0 == id }
        update(id) { $0.state = .paused }
        if active?.id == id {
            active?.task.cancel()
        }
    }

    /// Stops the transfer and deletes partial files. Completed files are kept.
    public func cancel(_ id: String) {
        queue.removeAll { $0 == id }
        if active?.id == id {
            active?.task.cancel()
        }
        if let recipe = recipes[id] {
            for component in storage.missingComponents(of: recipe) {
                let file = storage.url(for: component)
                try? FileManager.default.removeItem(at: FileDownloader.partialURL(for: file))
                try? FileManager.default.removeItem(at: FileDownloader.markerURL(for: file))
            }
        }
        statuses[id] = nil
        recipes[id] = nil
        publish()
    }

    /// Forgets a finished or failed entry.
    public func clear(_ id: String) {
        guard let status = statuses[id], !status.isActive else { return }
        statuses[id] = nil
        publish()
    }

    // MARK: - Running

    private func runNextIfIdle() {
        guard active == nil, !queue.isEmpty else { return }
        let id = queue.removeFirst()
        guard let recipe = recipes[id] else { return runNextIfIdle() }
        let task = Task { await self.run(recipe) }
        active = (id, task)
    }

    private func run(_ recipe: ModelRecipe) async {
        let id = recipe.id
        do {
            try checkDiskSpace(for: recipe)
            for component in recipe.components where !storage.isInstalled(component) {
                try Task.checkCancellation()
                let done = bytesOnDisk(for: recipe, excluding: component)
                update(id) { status in
                    status.state = .downloading
                    status.currentFile = component.file
                }
                let item = DownloadItem(
                    url: HFClient.downloadURL(repo: component.repo, file: component.file, revision: component.revision),
                    destination: storage.url(for: component),
                    expectedSize: component.sizeBytes,
                    sha256: component.sha256
                )
                try await downloader.download(item) { [weak self] event in
                    Task { await self?.handle(event, for: id, file: component.file, bytesBefore: done) }
                }
            }
            finish(id) { status in
                status.state = .completed
                status.currentFile = nil
                status.receivedBytes = status.totalBytes ?? status.receivedBytes
            }
        } catch is CancellationError {
            // pause() and cancel() already recorded the outcome.
            finish(id) { _ in }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            finish(id) { $0.state = .failed(message) }
        }
    }

    private func handle(_ event: TransferEvent, for id: String, file: String, bytesBefore: Int64) {
        // Late events from an earlier file, or from a transfer that was paused or
        // cancelled, must not change the current state.
        guard active?.id == id, let status = statuses[id], status.currentFile == file,
              status.state == .downloading || status.state == .verifying
        else {
            return
        }
        update(id) { status in
            switch event {
            case .progress(let received, _):
                // Events hop onto the actor one task each, so they can arrive out of order.
                status.receivedBytes = max(status.receivedBytes, bytesBefore + received)
            case .verifying:
                status.state = .verifying
            }
        }
    }

    private func finish(_ id: String, _ change: (inout DownloadStatus) -> Void) {
        if statuses[id] != nil {
            update(id, change)
        }
        if active?.id == id {
            active = nil
        }
        runNextIfIdle()
    }

    private func checkDiskSpace(for recipe: ModelRecipe) throws {
        var needed: Int64 = 0
        for component in storage.missingComponents(of: recipe) {
            let partial = FileDownloader.partialURL(for: storage.url(for: component))
            needed += max(0, (component.sizeBytes ?? 0) - Self.size(of: partial))
        }
        guard needed > 0, let available = freeSpace(storage.root) else { return }
        if available < needed {
            throw DownloadError.notEnoughDiskSpace(needed: needed, available: available)
        }
    }

    // MARK: - Bookkeeping

    /// Bytes already present for the recipe, counting finished and partial files.
    private func bytesOnDisk(for recipe: ModelRecipe, excluding excluded: ModelRecipe.Component? = nil) -> Int64 {
        recipe.components.reduce(0) { total, component in
            guard component != excluded else { return total }
            let file = storage.url(for: component)
            let finished = Self.size(of: file)
            return total + (finished > 0 ? finished : Self.size(of: FileDownloader.partialURL(for: file)))
        }
    }

    private static func size(of file: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func update(_ id: String, _ change: (inout DownloadStatus) -> Void) {
        var status = statuses[id] ?? DownloadStatus(state: .queued, receivedBytes: 0, totalBytes: nil, currentFile: nil)
        change(&status)
        guard statuses[id] != status else { return }
        statuses[id] = status
        publish()
    }

    private func publish() {
        for observer in observers.values {
            observer.yield(statuses)
        }
    }

    private func removeObserver(_ token: UUID) {
        observers[token] = nil
    }
}

/// What the user can do with one file of a Hugging Face repo.
public enum HubFileAvailability: Sendable, Equatable {
    /// Not on this Mac; it can be downloaded.
    case available
    /// Queued, downloading or being verified.
    case transferring(DownloadStatus)
    case installed
}

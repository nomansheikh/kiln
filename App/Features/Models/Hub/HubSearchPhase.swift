import KilnCore

/// Where a Hugging Face search currently stands.
enum HubSearchPhase {
    case loading
    case results([HFModelSummary])
    case failed(String)
}

/// Identifies one run of a search. Bumping `attempt` restarts the search task for the same query.
struct HubSearchKey: Equatable {
    var query: String
    var attempt: Int
}

/// Why the file list of a repo could not be loaded.
struct HubRepoFailure {
    var message: String
    /// True when access was refused, so an access token in Settings may help.
    var needsToken: Bool
}

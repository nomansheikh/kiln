import Foundation
import KilnCore
import Observation

/// The state behind `HubSearchResults`: the debounced search and the file lists
/// loaded for the repos the user has opened.
@MainActor
@Observable
final class HubSearchModel {
    private(set) var phase: HubSearchPhase = .loading
    private(set) var infos: [String: HFModelInfo] = [:]
    private(set) var loadingRepos: Set<String> = []
    private(set) var failures: [String: HubRepoFailure] = [:]

    /// How long typing has to pause before a search is sent.
    private static let debounce: Duration = .milliseconds(350)

    // MARK: - Searching

    /// Searches after a short pause; an empty query lists the most downloaded models
    /// at once. Cancelling the surrounding task, as happens while the user keeps
    /// typing, abandons the search without touching `phase`.
    func search(_ query: String, using hub: HFClient) async {
        phase = .loading
        do {
            if !query.isEmpty {
                try await Task.sleep(for: Self.debounce)
            }
            let summaries = try await hub.searchModels(query: query)
            guard !Task.isCancelled else { return }
            phase = .results(summaries)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    // MARK: - Repo files

    /// Loads the file list of a repo, unless it is already loaded or on its way.
    func loadInfo(for repo: String, using hub: HFClient) {
        guard infos[repo] == nil, !loadingRepos.contains(repo) else { return }
        loadingRepos.insert(repo)
        failures[repo] = nil
        Task {
            do {
                infos[repo] = try await hub.modelInfo(repo: repo)
            } catch {
                failures[repo] = HubRepoFailure(
                    message: Self.message(for: error),
                    needsToken: Self.needsToken(error)
                )
            }
            loadingRepos.remove(repo)
        }
    }

    // MARK: - Errors

    /// The message to show the user for a Hugging Face error.
    static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private static func needsToken(_ error: any Error) -> Bool {
        switch error as? HFError {
        case .accessDenied, .unauthorized: true
        default: false
        }
    }
}

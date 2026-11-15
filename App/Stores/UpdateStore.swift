import Foundation
import KilnCore
import Observation

/// Whether a newer version of Kiln exists, and whether the app looks for one.
/// It only tells the user: nothing is downloaded or installed.
@MainActor
@Observable
final class UpdateStore {
    private enum Key {
        static let isEnabled = "updates.checkEnabled"
        static let checkedAt = "updates.checkedAt"
        static let latestVersion = "updates.latestVersion"
        static let latestPage = "updates.latestPage"
        static let dismissedVersion = "updates.dismissedVersion"
    }

    /// The setting: on unless the user turned it off.
    var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Key.isEnabled)
            if isEnabled {
                Task { await checkIfDue() }
            }
        }
    }

    private var latest: PublishedRelease?
    private var dismissed: AppVersion?
    /// When this launch last tried, so a failed check is not repeated until tomorrow or the next launch.
    private var attemptedAt: Date?
    private var isChecking = false

    private let current: AppVersion?
    private let check: ReleaseCheck
    private let defaults: UserDefaults

    init(current: AppVersion? = AppVersion.current(), check: ReleaseCheck = ReleaseCheck(), defaults: UserDefaults = .standard) {
        self.current = current
        self.check = check
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        dismissed = defaults.string(forKey: Key.dismissedVersion).flatMap { AppVersion($0) }
        if let version = defaults.string(forKey: Key.latestVersion), let page = defaults.string(forKey: Key.latestPage) {
            latest = PublishedRelease(tag: version, page: page)
        }
        #if DEBUG
        if DebugSnapshot.showsSampleUpdate {
            latest = PublishedRelease(tag: "99.0.0", page: "https://github.com/nomansheikh/kiln/releases")
            dismissed = nil
        }
        #endif
    }

    /// The release to tell the user about: newer than this app and not dismissed.
    var available: PublishedRelease? {
        guard isEnabled, let latest, let current, latest.version > current, latest.version != dismissed else { return nil }
        return latest
    }

    /// Hides the notice until a version newer than this one is published.
    func dismiss() {
        guard let version = available?.version else { return }
        dismissed = version
        defaults.set(version.description, forKey: Key.dismissedVersion)
    }

    /// Checks now if a check is due, then looks again every hour, so an app
    /// that stays open for days still hears about a new version.
    func start() {
        #if DEBUG
        if DebugSnapshot.showsSampleUpdate { return }
        #endif
        Task {
            while !Task.isCancelled {
                await checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    /// Asks GitHub for the latest release at most once a day. Failing, for
    /// example offline or before the first release exists, changes nothing.
    private func checkIfDue() async {
        guard isEnabled, !isChecking, let current else { return }
        let checkedAt = defaults.object(forKey: Key.checkedAt) as? Date
        let lastCheck = [checkedAt, attemptedAt].compactMap { $0 }.max()
        guard ReleaseCheck.isDue(lastCheck: lastCheck) else { return }

        isChecking = true
        defer { isChecking = false }
        attemptedAt = Date()
        do {
            let update = try await check.update(for: current)
            defaults.set(Date(), forKey: Key.checkedAt)
            latest = update
            defaults.set(update?.version.description, forKey: Key.latestVersion)
            defaults.set(update?.pageURL.absoluteString, forKey: Key.latestPage)
        } catch {
            // Silent on purpose: the notice is a courtesy, and the check runs again later.
        }
    }
}

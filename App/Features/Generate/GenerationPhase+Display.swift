import KilnCore

/// How a generation phase is described on the Generate screen.
extension GenerationPhase {
    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }

    /// Completed share of the running generation, or `nil` when it cannot be measured.
    var progressFraction: Double? {
        if case .running(let progress) = self { progress.fraction } else { nil }
    }

    /// Headline for the progress placeholder.
    var progressTitle: String {
        switch self {
        case .idle, .failed: ""
        case .starting: "Starting…"
        case .loadingModel: "Loading model…"
        case .running(let progress):
            switch progress.stage {
            case .preparing: "Preparing"
            case .encodingPrompt: "Encoding prompt"
            case .sampling: "Generating image"
            case .decoding: "Decoding image"
            case .other(let name): name
            }
        }
    }

    /// Second line under the headline, when there is more to say.
    var progressDetail: String? {
        switch self {
        case .loadingModel:
            "The first load can take a while."
        case .running(let progress):
            if case .sampling = progress.stage, progress.total > 0 {
                "Step \(min(progress.completed, progress.total)) of \(progress.total)"
            } else {
                nil
            }
        default:
            nil
        }
    }
}

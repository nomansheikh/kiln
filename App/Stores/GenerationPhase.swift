import KilnCore

/// What the running generation is doing.
enum GenerationPhase: Equatable {
    case idle
    case starting
    case loadingModel
    case running(GenerationProgress)

    var isBusy: Bool { self != .idle }
}

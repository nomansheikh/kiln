import KilnCore

extension ObjectsStore {
    /// What a running generation is doing.
    enum Activity: Equatable {
        case idle
        case starting
        /// An image model is drawing the picture the object will be made from.
        case picturing(GenerationProgress?)
        case building(GenerationProgress)

        var fraction: Double? {
            switch self {
            case .building(let progress): progress.fraction
            case .picturing(let progress): progress?.fraction
            default: nil
            }
        }
    }
}

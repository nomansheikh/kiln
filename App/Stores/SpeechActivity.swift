import Foundation

extension SpeechStore {
    /// What a running generation is doing.
    enum Activity: Equatable {
        case idle
        case loadingModel
        case speaking

        var title: String {
            switch self {
            case .idle: ""
            case .loadingModel: "Loading model"
            case .speaking: "Generating speech"
            }
        }
    }
}

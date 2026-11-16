/// How much an attached image may change, in plain words.
public enum EditStrength: Double, CaseIterable, Identifiable, Sendable {
    case subtle = 0.35
    case balanced = 0.6
    case strong = 0.8

    public var id: Double { rawValue }

    public var title: String {
        switch self {
        case .subtle: "Subtle"
        case .balanced: "Balanced"
        case .strong: "Strong"
        }
    }

    public var explanation: String {
        switch self {
        case .subtle: "Keeps the picture, changes details"
        case .balanced: "Keeps the layout, reworks the look"
        case .strong: "Uses the picture as a loose guide"
        }
    }
}

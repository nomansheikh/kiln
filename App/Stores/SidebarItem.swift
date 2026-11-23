/// The app's top-level screens.
enum SidebarItem: String, CaseIterable, Identifiable {
    case generate, speech, objects, models, gallery, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: "Generate"
        case .speech: "Speech"
        case .objects: "3D"
        case .models: "Models"
        case .gallery: "Gallery"
        case .settings: "Settings"
        }
    }
}

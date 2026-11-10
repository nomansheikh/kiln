/// The app's top-level screens.
enum SidebarItem: String, CaseIterable, Identifiable {
    case generate, models, gallery, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .generate: "Generate"
        case .models: "Models"
        case .gallery: "Gallery"
        case .settings: "Settings"
        }
    }
}

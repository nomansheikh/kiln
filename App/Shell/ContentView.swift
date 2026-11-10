import SwiftUI

/// A floating sidebar beside a flat main area, as in Jan.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var sidebarVisible = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                Sidebar(isVisible: $sidebarVisible)
                    .frame(width: 250)
                    .background(Theme.sidebarGradient, in: RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous).strokeBorder(Theme.hairline))
                    .padding(8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                switch model.selection ?? .generate {
                case .generate: GenerateView()
                case .models: ModelsView()
                case .gallery: GalleryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // With the sidebar hidden the content must clear the traffic lights.
            .padding(.top, sidebarVisible ? 0 : 44)
            .overlay(alignment: .topLeading) {
                if !sidebarVisible {
                    SidebarToggle(isVisible: $sidebarVisible)
                        .padding(.leading, 88)
                        .padding(.top, 15)
                }
            }
        }
        .background(Theme.window)
        .ignoresSafeArea()
        .focusRingsWhileNavigating()
        .background(WindowChrome())
        .animation(.snappy(duration: 0.25), value: sidebarVisible)
    }
}

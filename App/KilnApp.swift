import AppKit
import KilnCore
import SwiftUI

@main
struct KilnApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .tint(Theme.accent)
                #if DEBUG
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--light") ? .light : nil)
                .task {
                    if let directory = DebugSnapshot.outputDirectory {
                        await DebugSnapshot.run(model: model, into: directory)
                    }
                }
                #endif
        }
        .defaultSize(width: 1220, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Image") { model.newImage() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Image") {
                Button("Generate") { model.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.canGenerate)
                Button("Stop") { model.cancelGeneration() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.phase.isBusy)
                Divider()
                Button("Unload Model") { model.unloadModel() }
                    .disabled(model.phase.isBusy)
            }
            CommandGroup(after: .sidebar) {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { model.selection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }
    }
}

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
        .background(WindowChrome())
        .animation(.snappy(duration: 0.25), value: sidebarVisible)
    }
}

/// Gives the window a taller, empty unified title area so the traffic lights
/// sit inside the floating sidebar instead of on its rounded corner.
private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            let toolbar = NSToolbar(identifier: "kiln.main")
            toolbar.showsBaselineSeparator = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct SidebarToggle: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                SidebarToggle(isVisible: $isVisible)
            }
            .padding(.trailing, 10)
            .frame(height: 36) // the traffic lights sit in this strip, centred on the toggle

            VStack(spacing: 1) {
                SidebarRow(title: "New image", symbol: "plus.bubble", shortcut: "\u{2318}N", selected: model.selection == .generate) {
                    model.newImage()
                }
                SidebarRow(title: "Models", symbol: "square.grid.2x2", shortcut: "\u{2318}2", selected: model.selection == .models,
                           badge: activeDownloads.count) {
                    model.selection = .models
                }
                SidebarRow(title: "Gallery", symbol: "photo.on.rectangle", shortcut: "\u{2318}3", selected: model.selection == .gallery) {
                    model.selection = .gallery
                }
                SidebarRow(title: "Settings", symbol: "gearshape", shortcut: "\u{2318}4", selected: model.selection == .settings) {
                    model.selection = .settings
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            recents

            Spacer(minLength: 8)

            if let download = activeDownloads.first {
                DownloadSummary(recipe: download.recipe, status: download.status)
                    .padding(10)
            }
        }
    }

    @ViewBuilder private var recents: some View {
        let items = Array(model.galleryItems.prefix(12))
        if !items.isEmpty {
            Text("Recent")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(items) { item in
                        RecentRow(item: item)
                    }
                }
                .padding(.horizontal, 8)
            }
            .scrollIndicators(.never)
        }
    }

    private var activeDownloads: [(recipe: ModelRecipe, status: DownloadStatus)] {
        model.recipes.compactMap { recipe in
            guard let status = model.downloadStatus(for: recipe), status.isActive else { return nil }
            return (recipe, status)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let shortcut: String
    let selected: Bool
    var badge = 0
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(title)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.accent, in: Capsule())
                } else {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(selected ? 0.08 : (hovering ? 0.045 : 0)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let item: GalleryItem
    @State private var hovering = false

    var body: some View {
        Button {
            model.show(item)
        } label: {
            HStack(spacing: 8) {
                Thumbnail(url: item.url, maxPixelSize: 96)
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(item.record.request.prompt)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                Color.primary.opacity(model.latestImage?.id == item.id && model.selection == .generate ? 0.08 : (hovering ? 0.045 : 0)),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.record.request.prompt)
    }
}

/// The download in progress, always visible at the bottom of the sidebar.
private struct DownloadSummary: View {
    @Environment(AppModel.self) private var model
    let recipe: ModelRecipe
    let status: DownloadStatus

    var body: some View {
        Button {
            model.selection = .models
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
                    Text(recipe.name).font(.caption.weight(.semibold)).lineLimit(1)
                }
                ProgressView(value: status.fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                Text(caption).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            .card(padding: 10, radius: 10)
        }
        .buttonStyle(.plain)
    }

    private var caption: String {
        switch status.state {
        case .queued: "Waiting…"
        case .verifying: "Verifying…"
        default: status.fraction.map { "\(Int($0 * 100))% downloaded" } ?? "Downloading…"
        }
    }
}

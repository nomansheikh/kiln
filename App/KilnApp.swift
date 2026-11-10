import AppKit
import KilnCore
import SwiftUI

@main
struct KilnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 620)
                .tint(Theme.accent)
                .task {
                    // A download or a generation keeps the app alive after its window closes.
                    AppDelegate.hasWorkInProgress = { [model] in
                        model.generation.phase.isBusy || !model.library.activeDownloads.isEmpty
                    }
                }
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
                Button("Generate") { model.generation.generate() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!model.generation.canGenerate)
                Button("Stop") { model.generation.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!model.generation.phase.isBusy)
                Divider()
                Button("Unload Model from Memory") { model.generation.unloadModel() }
                    .disabled(model.generation.phase.isBusy || model.generation.loadedRecipeID == nil)
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

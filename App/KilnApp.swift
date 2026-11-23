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
                        model.generation.phase.isBusy || model.speech.isUsingEngine || model.studio.isGenerating
                            || !model.library.activeDownloads.isEmpty
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
                Button("New Chat") { model.newChat() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandMenu("Generate") {
                // Both commands act on the screen in front: Speech, 3D, or the chat.
                let onSpeech = model.selection == .speech
                let on3D = model.selection == .objects
                Button(onSpeech ? "Generate Speech" : on3D ? "Make 3D Object" : "Generate") {
                    if onSpeech { model.speech.generate() } else if on3D { model.studio.generate() } else { model.generation.generate() }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(onSpeech ? !model.speech.canGenerate : on3D ? !model.studio.canGenerate : !model.generation.canGenerate)
                Button("Stop") {
                    if onSpeech { model.speech.cancel() } else if on3D { model.studio.cancel() } else { model.generation.cancel() }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(onSpeech ? !model.speech.isGenerating : on3D ? !model.studio.isGenerating : !model.generation.phase.isBusy)
                Divider()
                Button("Unload Model from Memory") { model.generation.unloadModel() }
                    .disabled(model.generation.phase.isBusy || model.speech.isUsingEngine || model.studio.isGenerating
                        || model.generation.loadedRecipeID == nil)
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

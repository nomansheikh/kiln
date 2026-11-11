import AppKit
import SwiftUI

/// The capsule search field in the Models header. It is not focused until the
/// user clicks it or presses Command-F; Escape clears it, and a click anywhere
/// else gives the focus up.
struct ModelsSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var clickMonitor: Any?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Hugging Face", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                clearButton
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(width: 250)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(isFocused ? Theme.accent.opacity(0.7) : Theme.hairline))
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onChange(of: isFocused) {
            if isFocused { watchClicks() } else { stopWatchingClicks() }
        }
        .onDisappear(perform: stopWatchingClicks)
        .task {
            // Opening the screen hands keyboard focus to its first text field.
            // Searching should be a choice, so give the focus back.
            try? await Task.sleep(for: .milliseconds(50))
            if text.isEmpty {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
        .background(
            // Command-F jumps to the search field.
            Button("Search") { isFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    /// macOS leaves a text field focused when the click lands on something that
    /// cannot take focus itself, which is most of this screen. While the field is
    /// focused, a click outside it ends editing.
    private func watchClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                guard let window = event.window, let editor = window.firstResponder as? NSText,
                      let hit = window.contentView?.superview?.hitTest(event.locationInWindow) else { return }
                // The field editor sits inside the text field; a hit on either is a click in the field.
                if !hit.isDescendant(of: editor), !(hit is NSTextField && editor.isDescendant(of: hit)) {
                    window.makeFirstResponder(nil)
                }
            }
            return event
        }
    }

    private func stopWatchingClicks() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }

    private var clearButton: some View {
        Button {
            text = ""
            isFocused = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Clear search")
        .accessibilityLabel("Clear search")
    }
}

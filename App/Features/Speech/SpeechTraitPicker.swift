import KilnCore
import SwiftUI

/// The traits of a voice being designed, for a model that takes fixed words:
/// each chosen word is a chip that can be removed, followed by a plus that
/// opens the words of the groups not used yet. One word may be chosen per group.
struct SpeechTraitPicker: View {
    let groups: [ModelRecipe.StyleGroup]
    /// The chosen words, at most one per group.
    @Binding var chosen: [String]
    @State private var showsOptions = false

    private var free: [ModelRecipe.StyleGroup] {
        groups.filter { group in !group.options.contains(where: chosen.contains) }
    }

    var body: some View {
        GenerateFlowLayout(spacing: 6, centred: false) {
            ForEach(groups.filter { $0.options.contains(where: chosen.contains) }, id: \.name) { group in
                chip(for: group)
            }
            if !free.isEmpty {
                Button { showsOptions.toggle() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        if chosen.isEmpty { Text("Add a trait").font(.callout) }
                    }
                    .foregroundStyle(showsOptions ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .padding(.horizontal, chosen.isEmpty ? 11 : 0)
                    .frame(minWidth: 30, minHeight: 30)
                    .background(Color.primary.opacity(showsOptions ? 0.1 : 0.06), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle(scale: 0.94))
                .pointerCursor()
                .focusable(false)
                .help("Add a trait")
                .accessibilityLabel("Add a trait")
                .popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                    SpeechTraitOptions(groups: free) { word, group in
                        chosen.removeAll(where: group.options.contains)
                        chosen.append(word)
                        // The list stays open for the next trait until every group has one.
                        if free.isEmpty { showsOptions = false }
                    }
                }
                #if DEBUG
                .task {
                    guard DebugSnapshot.opensStyleEditor else { return }
                    try? await Task.sleep(for: .milliseconds(700))
                    showsOptions = true
                }
                #endif
            }
        }
        .animation(.snappy(duration: 0.18), value: chosen)
    }

    /// A chosen word, with a button to take it away again.
    private func chip(for group: ModelRecipe.StyleGroup) -> some View {
        let word = group.options.first(where: chosen.contains) ?? ""
        return HStack(spacing: 6) {
            Text(verbatim: SpeechTraitOptions.title(word, in: group))
                .font(.callout.weight(.medium))
            Button { chosen.removeAll(where: group.options.contains) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color.primary.opacity(0.1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Remove")
            .accessibilityLabel("Remove \(word)")
        }
        .padding(.leading, 12)
        .padding(.trailing, 7)
        .frame(height: 30)
        .background(Theme.accent.opacity(0.2), in: Capsule())
        .help(group.name)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }
}

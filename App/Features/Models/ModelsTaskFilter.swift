import KilnCore
import SwiftUI

/// A row of chips that narrows the Models screen to one task, such as images
/// or speech to text. It appears only when the recipes cover more than one task.
struct ModelsTaskFilter: View {
    let recipes: [ModelRecipe]
    /// Raw value of the chosen `ModelTask`, or an empty string for every task.
    @Binding var selection: String

    var body: some View {
        let tasks = ModelTask.allCases.filter { task in recipes.contains { $0.task == task } }
        if tasks.count > 1 {
            // A stale choice, for a task no recipe has any more, counts as "All".
            let current = tasks.first { $0.rawValue == selection }
            HStack(spacing: 8) {
                chip("All", systemImage: "square.grid.2x2", isOn: current == nil) {
                    selection = ""
                }
                ForEach(tasks, id: \.self) { task in
                    chip(task.title, systemImage: task.symbolName, isOn: current == task) {
                        selection = task.rawValue
                    }
                }
            }
            .padding(.bottom, 2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Filter models by task")
        }
    }

    private func chip(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .imageScale(.small)
                Text(title)
            }
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(isOn ? Theme.accent : Color.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(isOn ? Theme.accent.opacity(0.14) : Theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.5) : Theme.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

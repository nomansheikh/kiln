import SwiftUI

/// The trailing controls of an installed recipe: delete its files, after confirming, or use it.
struct RecipeInstalledActions: View {
    let recipeName: String
    let delete: () throws -> Void
    let use: () -> Void

    @State private var isConfirmingDelete = false
    @State private var deleteError: String?

    var body: some View {
        HStack(spacing: 8) {
            ModelsIconButton(systemImage: "trash", help: "Delete this model's files", role: .destructive) {
                isConfirmingDelete = true
            }
            .accessibilityLabel("Delete \(recipeName)")
            .confirmationDialog("Delete \(recipeName)?", isPresented: $isConfirmingDelete) {
                Button("Delete Files", role: .destructive, action: confirmDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The downloaded files are removed from this Mac. You can download the model again later.")
            }
            .alert("Could Not Delete Model", isPresented: Binding(isPresenting: $deleteError)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }

            Button(action: use) {
                Label("Use", systemImage: "wand.and.stars")
            }
            .buttonStyle(AccentButtonStyle())
            .help("Generate images with this model")
        }
        .fixedSize()
    }

    private func confirmDelete() {
        do {
            try delete()
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

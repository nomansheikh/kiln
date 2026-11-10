import KilnCore

/// What can be done to a gallery image. The screen builds one and hands it to
/// the grid, the context menu and the detail panel, so they all act the same way.
struct GalleryItemActions {
    let reuseSettings: @MainActor (GalleryItem) -> Void
    let copyImage: @MainActor (GalleryItem) -> Void
    let showInFinder: @MainActor (GalleryItem) -> Void
    /// Asks for confirmation first; the screen owns the dialog.
    let delete: @MainActor (GalleryItem) -> Void
}

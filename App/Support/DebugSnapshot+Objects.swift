#if DEBUG
import Foundation
import KilnCore

/// Flags for picturing the 3D screen.
extension DebugSnapshot {
    /// `--objects <folder>` shows that folder's 3D objects instead of the user's own. An empty folder shows the screen's greeting.
    static var objectsDirectory: URL? {
        directory(after: "--objects")
    }

    /// `--sample-building <picture>` shows the 3D screen while an object is being made from that picture.
    static func loadSampleBuilding(into model: AppModel) {
        guard let picture = directory(after: "--sample-building") else { return }
        model.studio.loadPreview(
            activity: .building(GenerationProgress(stage: .building, completed: 36, total: 84)), picture: picture
        )
    }
}
#endif

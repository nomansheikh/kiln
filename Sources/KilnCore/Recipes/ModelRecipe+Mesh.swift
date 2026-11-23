import Foundation

/// What a recipe for a 3D model says through its files. trellis.cpp opens each
/// file by a fixed name, and names the files of a model other than TRELLIS.2
/// with that model's prefix, so the names are the statement.
extension ModelRecipe {
    /// The engine's name for the model: `pixal3d` when the main file carries that prefix, else `trellis`.
    public var meshFamily: String {
        let main = components.first { $0.role == .model }?.file ?? ""
        return Self.fileName(main).hasPrefix("pixal3d_") ? "pixal3d" : "trellis"
    }

    /// The levels of detail the model can colour. Standard needs a texture file
    /// made for it, which not every model publishes; the finer levels do not.
    public var meshDetails: [MeshSettings.Detail] {
        let colours512 = components.contains { Self.fileName($0.file).hasSuffix("tex_flow_512.gguf") }
        return MeshSettings.Detail.allCases.filter { $0 != .standard || colours512 }
    }

    private static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

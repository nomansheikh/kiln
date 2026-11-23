import AppKit
import KilnCore
import ModelIO
import SceneKit
import SceneKit.ModelIO
import UniformTypeIdentifiers

/// Saves a 3D object to a place the user picks, as the file it was made as or
/// converted for other apps.
@MainActor
enum MeshExporter {
    enum Format: String, CaseIterable, Identifiable {
        /// The object as the model wrote it: shape and colours in one file.
        case glb
        /// Apple's format, which Quick Look, Keynote and Reality Composer open.
        case usdz
        /// The shape alone, for apps that read nothing newer, such as slicers for 3D printing.
        case obj

        var id: String { rawValue }

        var title: String {
            switch self {
            case .glb: "GLB (shape and colours)"
            case .usdz: "USDZ (for Apple apps)"
            case .obj: "OBJ (shape only)"
            }
        }
    }

    static func save(_ item: MeshItem, as format: Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
        panel.nameFieldStringValue = item.url.deletingPathExtension().lastPathComponent + "." + format.rawValue
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            // The panel already asked before replacing an existing file.
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            switch format {
            case .glb:
                try FileManager.default.copyItem(at: item.url, to: destination)
            case .usdz, .obj:
                let scene = MeshScene.make(from: try MeshFile(glb: Data(contentsOf: item.url)), forExport: true)
                let written = format == .usdz
                    ? scene.write(to: destination, options: nil, delegate: nil, progressHandler: nil)
                    : ((try? MDLAsset(scnScene: scene).export(to: destination)) != nil)
                if !written { throw CocoaError(.fileWriteUnknown) }
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

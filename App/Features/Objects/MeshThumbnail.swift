import AppKit
import KilnCore
import Metal
import SceneKit

/// Makes the small picture of an object that lists show, and keeps it beside
/// the object so that it is rendered only once.
enum MeshThumbnail {
    /// The file holding the picture of an object, rendered and saved first if it is
    /// not there yet. Call it off the main thread. It answers with the file and not
    /// the image, because an image may not be handed from one thread to another.
    static func file(of item: MeshItem, side: CGFloat = 480) -> URL? {
        let file = MeshStore.picture(of: item.url)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        guard let data = try? Data(contentsOf: item.url), let mesh = try? MeshFile(glb: data) else { return nil }
        let image = render(MeshScene.make(from: mesh), side: side)
        guard let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]),
              (try? png.write(to: file, options: .atomic)) != nil
        else { return nil }
        return file
    }

    /// A still of a scene from its own camera, on a clear background.
    static func render(_ scene: SCNScene, side: CGFloat, width: CGFloat? = nil) -> NSImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: MeshScene.cameraName, recursively: false)
        scene.background.contents = NSColor.clear
        // The first frame is drawn before the room's light has been worked out, so it comes out dark.
        _ = renderer.snapshot(atTime: 0, with: CGSize(width: 64, height: 64), antialiasingMode: .none)
        return renderer.snapshot(atTime: 0, with: CGSize(width: width ?? side, height: side), antialiasingMode: .multisampling4X)
    }
}

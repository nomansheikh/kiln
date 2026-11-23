import AppKit
import KilnCore
import Metal
import SceneKit

/// Makes the small picture of an object that lists show, and keeps it beside
/// the object so that it is rendered only once.
enum MeshThumbnail {
    /// The picture of an object, rendered and saved if it is not there yet. Call it off the main thread.
    static func image(of item: MeshItem, side: CGFloat = 480) -> NSImage? {
        let file = MeshStore.picture(of: item.url)
        if let saved = NSImage(contentsOf: file) { return saved }
        guard let data = try? Data(contentsOf: item.url), let mesh = try? MeshFile(glb: data) else { return nil }
        let image = render(MeshScene.make(from: mesh), side: side)
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: file, options: .atomic)
        }
        return image
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

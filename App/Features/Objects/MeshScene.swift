import AppKit
import KilnCore
import SceneKit

/// Builds the SceneKit scene that shows a 3D object the way a product is
/// photographed: on a turntable, under soft studio light, with its shadow on
/// the ground beneath it.
enum MeshScene {
    /// How the surface is drawn.
    enum Look: String, CaseIterable, Identifiable {
        case colour, clay, wire

        var id: String { rawValue }

        var title: String {
            switch self {
            case .colour: "Colour"
            case .clay: "Clay"
            case .wire: "Wireframe"
            }
        }

        var symbolName: String {
            switch self {
            case .colour: "paintpalette"
            case .clay: "circle.lefthalf.filled"
            case .wire: "square.grid.3x3"
            }
        }
    }

    static let turntableName = "turntable"
    static let cameraName = "camera"

    /// - Parameter forExport: Leaves out the ground, the camera and the lights, which belong to the viewer and not to the object.
    static func make(from mesh: MeshFile, forExport: Bool = false) -> SCNScene {
        let count = mesh.vertexCount
        var sources = [source(mesh.positions, .vertex, components: 3, count: count)]
        if let normals = mesh.normals {
            sources.append(source(normals, .normal, components: 3, count: count))
        }
        if let coordinates = mesh.textureCoordinates {
            sources.append(source(coordinates, .texcoord, components: 2, count: count))
        }
        let element = SCNGeometryElement(
            data: mesh.indices, primitiveType: .triangles, primitiveCount: mesh.triangleCount, bytesPerIndex: 4
        )
        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.materials = [material(of: mesh, look: .colour)]

        let low = mesh.lowerBound.map(CGFloat.init), high = mesh.upperBound.map(CGFloat.init)
        let size = max(high[0] - low[0], high[1] - low[1], high[2] - low[2], 0.001)
        let scene = SCNScene()

        // Centred on the turntable, standing on the ground.
        let object = SCNNode(geometry: geometry)
        object.position = SCNVector3(-(low[0] + high[0]) / 2, -low[1], -(low[2] + high[2]) / 2)
        object.castsShadow = true
        let turntable = SCNNode()
        turntable.name = turntableName
        turntable.addChildNode(object)
        turntable.eulerAngles.y = .pi / 7
        scene.rootNode.addChildNode(turntable)

        if forExport {
            turntable.eulerAngles.y = 0
            return scene
        }

        // A ground that shows nothing but the shadow falling on it.
        let ground = SCNNode(geometry: SCNPlane(width: size * 12, height: size * 12))
        ground.eulerAngles.x = -.pi / 2
        ground.geometry?.firstMaterial?.lightingModel = .shadowOnly
        ground.castsShadow = false
        scene.rootNode.addChildNode(ground)

        let height = high[1] - low[1]
        let camera = SCNNode()
        camera.name = cameraName
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 30
        camera.camera?.zNear = Double(size) / 50
        camera.camera?.zFar = Double(size) * 80
        // Tone mapping keeps a pale or shiny surface from burning out to white.
        camera.camera?.wantsHDR = true
        camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.35
        camera.camera?.whitePoint = 1.6
        camera.position = SCNVector3(0, height * 0.62, size * 2.55)
        camera.look(at: SCNVector3(0, height * 0.46, 0))
        scene.rootNode.addChildNode(camera)

        addLights(to: scene, size: size)
        return scene
    }

    /// Changes how the object's surface is drawn.
    static func apply(_ look: Look, to scene: SCNScene, mesh: MeshFile) {
        scene.rootNode.childNode(withName: turntableName, recursively: false)?
            .childNodes.first?.geometry?.materials = [material(of: mesh, look: look)]
    }

    /// Even light from everywhere, a key lamp that casts the shadow, and a
    /// faint one from behind that separates the object from the backdrop.
    private static func addLights(to scene: SCNScene, size: CGFloat) {
        // Brighter above than below, like a room with a pale ceiling. A shiny surface
        // mirrors its surroundings, and an evenly white room would turn it plain white.
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 0.9

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 620
        key.light?.castsShadow = true
        key.light?.shadowMode = .forward
        key.light?.shadowColor = NSColor(white: 0, alpha: 0.38)
        key.light?.shadowRadius = 14
        key.light?.shadowSampleCount = 24
        key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.orthographicScale = size * 3
        key.light?.zFar = size * 20
        // High and a little to one side, so the shadow stays close under the object.
        key.position = SCNVector3(size * 0.7, size * 3.4, size * 1.3)
        key.look(at: SCNVector3(0, size * 0.4, 0))
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 260
        rim.position = SCNVector3(-size * 2, size * 1.6, -size * 2.5)
        rim.look(at: SCNVector3(0, size * 0.5, 0))
        scene.rootNode.addChildNode(rim)
    }

    /// The room the object stands in, as a picture wrapped around it: pale above, dim below.
    /// Made for each scene: it is tiny, and a shared image would be shared mutable state.
    private static var studio: NSImage {
        let size = NSSize(width: 64, height: 32)
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0.22, alpha: 1), NSColor(white: 0.62, alpha: 1), NSColor(white: 0.98, alpha: 1)])?
                .draw(in: rect, angle: 90)
            return true
        }
    }

    private static func source(_ data: Data, _ semantic: SCNGeometrySource.Semantic, components: Int, count: Int) -> SCNGeometrySource {
        SCNGeometrySource(
            data: data, semantic: semantic, vectorCount: count, usesFloatComponents: true, componentsPerVector: components,
            bytesPerComponent: 4, dataOffset: 0, dataStride: 4 * components
        )
    }

    private static func material(of mesh: MeshFile, look: Look) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        // A surface without normals would otherwise be lit from one side only.
        material.isDoubleSided = mesh.normals == nil || look == .wire
        let surface = mesh.metallicRoughnessImage.flatMap(NSImage.init(data:))
        switch look {
        case .colour:
            material.diffuse.contents = mesh.baseColorImage.flatMap(NSImage.init(data:)) ?? NSColor(white: 0.72, alpha: 1)
            // The file also says how metallic each part is, in the blue channel. The
            // model guesses that badly (the same object comes out at 4% one run and
            // 99% the next), and a metal mirrors the room instead of showing its
            // colour, so the viewer leaves it out. The saved file keeps it.
            material.metalness.contents = 0.0
            if let surface {
                // glTF keeps roughness in the green channel.
                material.roughness.contents = surface
                material.roughness.textureComponents = .green
            } else {
                material.roughness.contents = 0.8
            }
        case .clay:
            material.diffuse.contents = NSColor(calibratedRed: 0.80, green: 0.78, blue: 0.75, alpha: 1)
            material.roughness.contents = 0.62
            material.metalness.contents = 0.0
        case .wire:
            material.diffuse.contents = NSColor(calibratedRed: 0.36, green: 0.72, blue: 0.90, alpha: 1)
            material.lightingModel = .constant
            material.fillMode = .lines
        }
        return material
    }
}

import KilnCore
import SceneKit
import SwiftUI

/// The live view of a 3D object. Dragging turns it, scrolling zooms, and it
/// turns slowly by itself until it is touched: from then on the hand decides.
struct MeshStageView: NSViewRepresentable {
    let scene: SCNScene
    /// Whether the object turns by itself. Off with Reduce Motion.
    var turns: Bool
    /// Changes to put the camera back where it started.
    var resetToken: Int
    /// Called when the user starts to move the view. Turning on while they do would fight their hand.
    var onTouch: () -> Void = {}

    func makeNSView(context: Context) -> SCNView {
        let view = TouchReportingSceneView()
        view.onTouch = onTouch
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = true
        // Nearly all the way round, top and bottom: only the poles are left out, where the view would flip.
        view.defaultCameraController.minimumVerticalAngle = -85
        view.defaultCameraController.maximumVerticalAngle = 85
        // Jittering is left off: on a still frame it asks Metal for a texture the view
        // has no size for yet, and the app aborts. Multisampling smooths the edges.
        view.rendersContinuously = false
        show(scene, in: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        (view as? TouchReportingSceneView)?.onTouch = onTouch
        if view.scene !== scene || context.coordinator.resetToken != resetToken {
            show(scene, in: view, coordinator: context.coordinator)
        }
        setTurning(turns, in: scene)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var resetToken = 0
    }

    private func show(_ scene: SCNScene, in view: SCNView, coordinator: Coordinator) {
        coordinator.resetToken = resetToken
        view.scene = scene
        view.pointOfView = scene.rootNode.childNode(withName: MeshScene.cameraName, recursively: false)
        scene.rootNode.childNode(withName: MeshScene.turntableName, recursively: false)?.eulerAngles.y = .pi / 7
        setTurning(turns, in: scene)
    }

    /// One slow turn every 24 seconds: enough to show the back without hurrying the eye.
    private func setTurning(_ turning: Bool, in scene: SCNScene) {
        guard let turntable = scene.rootNode.childNode(withName: MeshScene.turntableName, recursively: false) else { return }
        let key = "turn"
        if turning, turntable.action(forKey: key) == nil {
            turntable.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 24)), forKey: key)
        } else if !turning {
            turntable.removeAction(forKey: key)
        }
    }
}

/// A scene view that says when the user begins to drag, scroll or pinch in it.
final class TouchReportingSceneView: SCNView {
    var onTouch: () -> Void = {}

    override func mouseDown(with event: NSEvent) {
        onTouch()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onTouch()
        super.rightMouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        onTouch()
        super.scrollWheel(with: event)
    }

    override func magnify(with event: NSEvent) {
        onTouch()
        super.magnify(with: event)
    }

    override func rotate(with event: NSEvent) {
        onTouch()
        super.rotate(with: event)
    }
}

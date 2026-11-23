import KilnCore
import SceneKit
import SwiftUI

/// The large area of the 3D screen: the object on its turntable, with the
/// controls for looking at it laid over the corners.
struct ObjectsStage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    let item: MeshItem

    @State private var mesh: MeshFile?
    @State private var scene: SCNScene?
    @State private var problem: String?
    @State private var look = MeshScene.Look.colour
    @State private var turns = true
    @State private var resetToken = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack {
            StageBackdrop()
            if let scene {
                live(scene)
                    .transition(.opacity)
            } else if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView()
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.hairline))
        .overlay(alignment: .topTrailing) { lookPicker.padding(12) }
        .overlay(alignment: .bottomLeading) { caption.padding(14) }
        .overlay(alignment: .bottomTrailing) { viewControls.padding(12) }
        .animation(Motion.layout(reduced: reduceMotion), value: scene != nil)
        .task(id: item.id) { await load() }
        .onChange(of: look) { _, look in
            if let scene, let mesh { MeshScene.apply(look, to: scene, mesh: mesh) }
        }
    }

    /// The view that can be turned. A snapshot cannot capture it, so there a still of the same scene stands in.
    @ViewBuilder
    private func live(_ scene: SCNScene) -> some View {
        #if DEBUG
        if DebugSnapshot.outputDirectory != nil {
            Color.clear.overlay { Image(nsImage: MeshThumbnail.render(scene, side: 1400, width: 2800)).resizable().scaledToFill() }
        } else {
            MeshStageView(scene: scene, turns: turns && !reduceMotion, resetToken: resetToken) { turns = false }
        }
        #else
        MeshStageView(scene: scene, turns: turns && !reduceMotion, resetToken: resetToken) { turns = false }
        #endif
    }

    private var lookPicker: some View {
        HStack(spacing: 2) {
            ForEach(MeshScene.Look.allCases) { option in
                Button { look = option } label: {
                    Image(systemName: option.symbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(look == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(width: 30, height: 26)
                        .background(look == option ? Color.primary.opacity(0.12) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .hint(option.title, alignment: .bottom)
            }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }

    private var viewControls: some View {
        HStack(spacing: 6) {
            if !reduceMotion {
                StageButton(systemImage: turns ? "pause.fill" : "arrow.triangle.2.circlepath", help: turns ? "Stop turning" : "Turn slowly") {
                    turns.toggle()
                }
            }
            StageButton(systemImage: "scope", help: "Put the view back") {
                resetToken += 1
                turns = true
            }
        }
    }

    /// What the object is made of, in numbers: a quiet line in the corner.
    @ViewBuilder
    private var caption: some View {
        if let mesh {
            Text("\(mesh.triangleCount.formatted()) triangles \u{00B7} drag to turn, scroll to zoom")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(.regularMaterial, in: Capsule())
        }
    }

    /// Reads the file off the main thread: an object has hundreds of thousands of corners.
    private func load() async {
        scene = nil
        problem = nil
        look = .colour
        let url = item.url
        let result = await Task.detached { () -> Result<MeshFile, any Error> in
            Result { try MeshFile(glb: Data(contentsOf: url)) }
        }.value
        switch result {
        case .success(let read):
            mesh = read
            scene = MeshScene.make(from: read)
        case .failure(let error):
            problem = (error as? LocalizedError)?.errorDescription ?? "The 3D object could not be opened."
        }
    }
}

/// The studio wall behind an object: light falling off towards the corners,
/// with a brighter pool where the object stands.
struct StageBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            (dark ? Color(white: 0.105) : Color(white: 0.93))
            RadialGradient(
                colors: [dark ? Color(white: 0.27) : Color.white, .clear],
                center: UnitPoint(x: 0.5, y: 0.56), startRadius: 0, endRadius: 520
            )
            LinearGradient(colors: [.clear, .black.opacity(dark ? 0.28 : 0.07)], startPoint: .center, endPoint: .bottom)
        }
    }
}

/// A round button laid over the stage.
struct StageButton: View {
    let systemImage: String
    let help: String
    /// Where the hint appears, for a button near an edge of the stage.
    var hintAlignment = Alignment.topTrailing
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .pointerCursor()
        .hint(help, alignment: hintAlignment)
    }
}

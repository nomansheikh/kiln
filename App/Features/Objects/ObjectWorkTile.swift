import SwiftUI

/// The first tile on the shelf while something is being made: its picture
/// under a ring that fills as the work goes on. Clicking it brings the work
/// back to the stage after looking at another object.
struct ObjectWorkTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The picture being worked from, or nil while one is still being drawn.
    let picture: URL?
    /// How far along the work is, or nil when that is not known.
    let fraction: Double?
    /// False for a drawn picture that waits to be approved.
    let isWorking: Bool
    let selected: Bool
    let action: () -> Void

    @State private var spins = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: action) {
            ZStack {
                StageBackdrop()
                if let picture {
                    Thumbnail(url: picture, maxPixelSize: 240)
                        .opacity(isWorking ? 0.45 : 1)
                } else {
                    Image(systemName: "paintbrush.pointed")
                        .foregroundStyle(.tertiary)
                }
                if isWorking {
                    ring
                } else {
                    Image(systemName: "questionmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: Circle())
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(shape)
            .overlay(shape.strokeBorder(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableButtonStyle(scale: 0.95))
        .pointerCursor()
        .hint(hintText, alignment: .topLeading)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spins = true }
        }
    }

    /// A ring that fills with the work, or turns while its length is not known.
    private var ring: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.45))
                .frame(width: 40, height: 40)
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 3)
                .frame(width: 30, height: 30)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 30, height: 30)
                    .rotationEffect(.degrees(spins ? 270 : -90))
            }
        }
    }

    private var hintText: String {
        guard isWorking else { return "A picture is waiting for your answer" }
        guard let fraction else { return "Being made: getting ready" }
        return "Being made: \(fraction.formatted(.percent.precision(.fractionLength(0))))"
    }
}

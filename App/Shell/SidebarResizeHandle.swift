import AppKit
import SwiftUI

/// An invisible strip on the sidebar's trailing edge that resizes it when dragged.
/// Double-click returns the sidebar to its default width.
struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var widthAtDragStart: Double?
    @State private var hovering = false

    static let defaultWidth: Double = 250
    static let range: ClosedRange<Double> = 200...420

    var body: some View {
        Color.clear
            .frame(width: 10)
            .contentShape(Rectangle())
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = widthAtDragStart ?? width
                        widthAtDragStart = start
                        width = min(max(start + drag.translation.width, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in widthAtDragStart = nil }
            )
            .onTapGesture(count: 2) { width = Self.defaultWidth }
            .accessibilityLabel("Resize sidebar")
            .accessibilityValue("\(Int(width)) points")
            .accessibilityAdjustableAction { direction in
                let step: Double = direction == .increment ? 20 : -20
                width = min(max(width + step, Self.range.lowerBound), Self.range.upperBound)
            }
    }
}

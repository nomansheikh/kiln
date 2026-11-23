import AppKit
import Observation
import SwiftUI

/// A small label that appears beside a control when the pointer rests on it,
/// saying what the control does. It comes up sooner than the system's own
/// tooltip, which icon-only buttons need: without it they are guesswork.
struct HoverHint: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    /// Where the label sits: above or below the control, and which side it lines up with.
    var alignment: Alignment = .top

    @State private var shown = false
    @State private var waiting: Task<Void, Never>?
    private let presses = HintDismissal.shared

    /// Height of the label, and the gap between it and the control.
    private static let height: CGFloat = 24
    private static let gap: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                waiting?.cancel()
                if inside {
                    waiting = Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        if !Task.isCancelled { shown = true }
                    }
                } else {
                    shown = false
                }
            }
            // A click or a key answers the question the label was about to. A menu that
            // opens takes the pointer with it, so the pointer leaving is never reported:
            // any press anywhere in the app puts the label away.
            .onChange(of: presses.count) {
                waiting?.cancel()
                shown = false
            }
            .task(id: shown) {
                // A label nobody is reading any more should not stay.
                guard shown else { return }
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled { shown = false }
            }
            .overlay(alignment: alignment) {
                if shown {
                    Text(text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(height: Self.height)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.hairline))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                        // Clear of the control, on the far side from it.
                        .offset(y: alignment.vertical == .top ? -(Self.height + Self.gap) : Self.height + Self.gap)
                        .allowsHitTesting(false)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                        .accessibilityHidden(true)
                }
            }
            // Above its neighbours, which would otherwise be drawn over the label.
            .zIndex(shown ? 10 : 0)
            .animation(.easeOut(duration: 0.12), value: shown)
            .accessibilityLabel(text)
    }
}

/// Counts presses anywhere in the app, so that every hint can leave when one happens.
@MainActor
@Observable
final class HintDismissal {
    static let shared = HintDismissal()
    private(set) var count = 0

    private init() {
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] event in
            self?.count &+= 1
            return event
        }
    }
}

extension View {
    /// Says what a control does when the pointer rests on it. See `HoverHint`.
    func hint(_ text: String, alignment: Alignment = .top) -> some View {
        modifier(HoverHint(text: text, alignment: alignment))
    }
}

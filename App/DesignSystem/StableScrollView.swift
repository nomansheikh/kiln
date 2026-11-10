import AppKit
import SwiftUI

/// A vertical scroll view whose content keeps the same width and position
/// whether or not the scroll bar is showing.
///
/// With macOS set to always show scroll bars, the bar takes its own strip of
/// width and disappears when the content gets short, which would otherwise
/// shift everything sideways as sections collapse and lists load.
struct StableScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(width: max(0, proxy.size.width - Self.scrollBarGutter))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Width reserved for an always-visible scroll bar; overlay scroll bars need none.
    private static var scrollBarGutter: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
            : 0
    }
}

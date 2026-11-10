import SwiftUI

struct SidebarToggle: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            isVisible.toggle()
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

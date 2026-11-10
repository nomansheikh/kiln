import KilnCore
import SwiftUI

/// Coloured dot with a label saying whether a model fits this Mac's memory.
struct FitLabel: View {
    let fit: MemoryFit
    let memoryGB: Int
    var compact = false

    private var color: Color {
        switch fit {
        case .comfortable: .green
        case .tight: .yellow
        case .tooLarge: .red
        }
    }

    private var text: String {
        switch fit {
        case .comfortable: "Fits your \(memoryGB) GB Mac"
        case .tight: "Tight fit on \(memoryGB) GB"
        case .tooLarge: "Needs more than \(memoryGB) GB"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            if !compact {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        }
        .help(text)
    }
}

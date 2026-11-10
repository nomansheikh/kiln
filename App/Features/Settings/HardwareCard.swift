import KilnCore
import SwiftUI

/// The chip, the memory models may use, and the macOS version.
struct HardwareCard: View {
    @Environment(AppModel.self) private var model

    private var totalGB: Double { Double(model.library.memory.physicalMemoryGB) }

    private var usableGB: Double { Double(model.library.memory.usableBytes) / 1_073_741_824 }

    private var usableFraction: Double {
        guard totalGB > 0 else { return 0 }
        return min(max(usableGB / totalGB, 0), 1)
    }

    private var memorySummary: String {
        let usable = usableGB.formatted(.number.precision(.fractionLength(1)))
        let total = totalGB.formatted(.number.precision(.fractionLength(0)))
        return "\(usable) GB of \(total) GB available to models"
    }

    var body: some View {
        SettingsCard(title: "Hardware", symbol: "cpu", description: "What this Mac gives models to work with") {
            SettingsRow("Chip", value: SystemInfo.chipName)
            SettingsRowDivider()
            memory
            SettingsRowDivider()
            SettingsRow("macOS", value: SystemInfo.osVersion)
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .fontWeight(.medium)
                Spacer(minLength: 12)
                Text(memorySummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            SettingsMemoryBar(fraction: usableFraction)

            Text("Kiln leaves room for macOS and your other apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

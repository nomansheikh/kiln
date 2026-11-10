import Foundation

public enum MemoryFit: Sendable, Equatable {
    case comfortable
    case tight
    case tooLarge
}

/// Estimates whether a recipe's weights fit in this Mac's unified memory.
///
/// This is a heuristic on file sizes only. It ignores the working memory that
/// grows with image resolution, so `comfortable` is not a guarantee.
public struct MemoryFitEstimator: Sendable {
    public var physicalMemoryBytes: UInt64

    public init(physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    static let bytesPerGB: Double = 1_073_741_824
    /// Fixed allowance for macOS itself, on top of a 10% share of RAM.
    static let systemReserveBytes: Double = 2.5 * bytesPerGB
    static let comfortableShare: Double = 0.85

    public var physicalMemoryGB: Double {
        Double(physicalMemoryBytes) / Self.bytesPerGB
    }

    /// Memory the model can realistically use.
    public var usableBytes: Double {
        let total = Double(physicalMemoryBytes)
        return max(0, total - Self.systemReserveBytes - total * 0.1)
    }

    /// Nil when the recipe declares neither file sizes nor a memory minimum.
    public func fit(for recipe: ModelRecipe) -> MemoryFit? {
        if let minimum = recipe.minMemoryGB, physicalMemoryGB < minimum {
            return .tooLarge
        }
        guard let size = recipe.totalSizeBytes else {
            return recipe.minMemoryGB == nil ? nil : .comfortable
        }
        let required = Double(size)
        if required > usableBytes { return .tooLarge }
        return required <= usableBytes * Self.comfortableShare ? .comfortable : .tight
    }
}

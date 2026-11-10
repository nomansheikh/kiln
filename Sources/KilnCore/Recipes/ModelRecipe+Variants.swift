import Foundation

extension ModelRecipe {
    /// One way to install the model: the files that differ from the recipe's
    /// shared `components`, typically a quantization of the large parts.
    public struct Variant: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        /// Shown in the app, for example "Q8 (best quality)".
        public var name: String
        /// Files for this variant. One with the same role as a shared component replaces it.
        public var components: [Component]
        public var minMemoryGB: Double?

        public init(id: String, name: String, components: [Component], minMemoryGB: Double? = nil) {
            self.id = id
            self.name = name
            self.components = components
            self.minMemoryGB = minMemoryGB
        }

        enum CodingKeys: String, CodingKey {
            case id, name, components
            case minMemoryGB = "min_memory_gb"
        }
    }

    public var hasVariants: Bool {
        !(variants ?? []).isEmpty
    }

    /// The recipe with one variant's files merged in, ready to download and run.
    /// A recipe without variants, or an unknown id, is returned unchanged.
    public func resolved(_ variantID: String) -> ModelRecipe {
        guard let variant = variants?.first(where: { $0.id == variantID }) else { return self }
        var recipe = self
        let replaced = Set(variant.components.map(\.role))
        recipe.components = components.filter { !replaced.contains($0.role) } + variant.components
        recipe.minMemoryGB = variant.minMemoryGB ?? minMemoryGB
        recipe.selectedVariantID = variant.id
        return recipe
    }

    /// Every variant as a runnable recipe, in the order the recipe lists them.
    public var resolvedVariants: [ModelRecipe] {
        (variants ?? []).map { resolved($0.id) }
    }
}

extension MemoryFitEstimator {
    /// The variant to offer first on this Mac: the largest that fits comfortably,
    /// since larger usually means higher quality; failing that the largest that
    /// fits at all, and otherwise the smallest.
    public func bestVariant(of recipe: ModelRecipe) -> ModelRecipe? {
        let candidates = recipe.resolvedVariants
        func largest(_ wanted: MemoryFit) -> ModelRecipe? {
            candidates
                .filter { fit(for: $0) == wanted }
                .max { ($0.totalSizeBytes ?? 0) < ($1.totalSizeBytes ?? 0) }
        }
        return largest(.comfortable) ?? largest(.tight)
            ?? candidates.min { ($0.totalSizeBytes ?? .max) < ($1.totalSizeBytes ?? .max) }
    }
}

import KilnCore

extension MemoryFitEstimator {
    /// How well a single weights file of the given size fits this Mac's memory.
    /// Same thresholds as the estimate for a whole recipe.
    func fit(forFileOfSize size: some BinaryInteger) -> MemoryFit {
        let required = Double(size)
        if required <= usableBytes * 0.85 {
            return .comfortable
        }
        return required <= usableBytes ? .tight : .tooLarge
    }
}

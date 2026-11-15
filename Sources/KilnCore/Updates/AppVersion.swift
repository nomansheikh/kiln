import Foundation

/// A version made of dotted numbers, such as `0.2.0`, with an optional leading `v`.
///
/// Missing components count as zero, so `0.1` equals `0.1.0`. Anything else,
/// such as `0.2.0-beta`, is not a version and does not parse.
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    private static let maximumComponents = 8
    private static let maximumDigits = 9

    /// The version as written, without the leading `v`.
    public let description: String
    /// The numbers, without trailing zeros, so equal versions hold equal lists.
    private let components: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...Self.maximumComponents).contains(parts.count) else { return nil }

        var numbers: [Int] = []
        for part in parts {
            // The tag is remote input: plain ASCII digits only, and short enough not to overflow.
            guard !part.isEmpty, part.count <= Self.maximumDigits,
                  part.utf8.allSatisfy({ (48...57).contains($0) }), let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        while numbers.last == 0 {
            numbers.removeLast()
        }
        description = text
        components = numbers
    }

    /// The version of the running app, or nil for a build without a readable one.
    public static func current(in bundle: Bundle = .main) -> AppVersion? {
        (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap { AppVersion($0) }
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.components == rhs.components
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(components)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

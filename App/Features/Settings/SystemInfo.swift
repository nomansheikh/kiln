import Foundation

/// Facts about this Mac shown on the Hardware card.
enum SystemInfo {
    /// The processor's marketing name, such as "Apple M3 Pro".
    static var chipName: String {
        let key = "machdep.cpu.brand_string"
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown"
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else {
            return "Unknown"
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }
}

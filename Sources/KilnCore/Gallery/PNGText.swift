import Foundation

/// Reads and writes PNG text chunks.
///
/// ImageIO does not round-trip arbitrary PNG text, and other Stable Diffusion
/// tools look for a chunk named `parameters`, so the chunks are handled directly.
enum PNGText {
    private static let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    /// Signature, then the IHDR chunk: 4 length + 4 type + 13 data + 4 CRC.
    private static let headerEnd = 8 + 25

    /// Adds UTF-8 `iTXt` chunks right after the image header.
    static func inserting(_ entries: [(keyword: String, text: String)], into png: Data) -> Data? {
        guard png.count > headerEnd, png.prefix(8) == signature else { return nil }
        var chunks = Data()
        for entry in entries {
            // keyword, NUL, compression flag, compression method, empty language, NUL, empty translated keyword, NUL, text
            var body = Data(entry.keyword.utf8)
            body.append(contentsOf: [0, 0, 0, 0, 0])
            body.append(Data(entry.text.utf8))

            var typeAndBody = Data("iTXt".utf8)
            typeAndBody.append(body)
            chunks.append(bigEndian(UInt32(body.count)))
            chunks.append(typeAndBody)
            chunks.append(bigEndian(crc32(typeAndBody)))
        }
        var result = Data(png.prefix(headerEnd))
        result.append(chunks)
        result.append(png.suffix(from: png.startIndex + headerEnd))
        return result
    }

    /// Text chunks that appear before the pixel data, without reading the pixels.
    static func entries(in file: URL) -> [String: String] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [:] }
        defer { try? handle.close() }
        guard (try? handle.read(upToCount: 8)) == signature else { return [:] }

        var entries: [String: String] = [:]
        while let header = try? handle.read(upToCount: 8), header.count == 8 {
            let length = header.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let type = String(decoding: header.suffix(4), as: UTF8.self)
            guard type != "IDAT", type != "IEND", length < 16 << 20 else { break }

            if type == "iTXt" || type == "tEXt" {
                guard let body = try? handle.read(upToCount: Int(length)), body.count == Int(length) else { break }
                if let (keyword, text) = decode(body, type: type) {
                    entries[keyword] = text
                }
                _ = try? handle.read(upToCount: 4)
            } else {
                guard let offset = try? handle.offset(), (try? handle.seek(toOffset: offset + length + 4)) != nil else { break }
            }
        }
        return entries
    }

    private static func decode(_ body: Data, type: String) -> (String, String)? {
        guard let keywordEnd = body.firstIndex(of: 0) else { return nil }
        let keyword = String(decoding: body[body.startIndex..<keywordEnd], as: UTF8.self)
        var rest = body[body.index(after: keywordEnd)...]
        if type == "tEXt" {
            return (keyword, String(decoding: rest, as: UTF8.self))
        }
        // Compressed iTXt is never written by Kiln and is skipped.
        guard rest.count >= 2, rest.first == 0 else { return nil }
        rest = rest.dropFirst(2)
        for _ in 0..<2 {
            guard let end = rest.firstIndex(of: 0) else { return nil }
            rest = rest[rest.index(after: end)...]
        }
        return (keyword, String(decoding: rest, as: UTF8.self))
    }

    private static func bigEndian(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        (0..<8).reduce(UInt32(index)) { value, _ in
            value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in
            crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
    }
}

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import KilnCore

@Suite struct GalleryTests {
    let store: GalleryStore

    init() {
        store = GalleryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("kiln-gallery-\(UUID().uuidString)"))
    }

    private func image(width: Int = 4, height: Int = 2, channels: Int = 3) -> GeneratedImage {
        let pixels = Data((0..<(width * height * channels)).map { UInt8($0 * 9 % 256) })
        return GeneratedImage(width: width, height: height, channels: channels, pixels: pixels)
    }

    private func record(prompt: String = "a red fox", createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> GenerationRecord {
        GenerationRecord(
            createdAt: createdAt,
            recipeID: "qwen-image-2.1-turbo",
            recipeName: "Qwen-Image 2.1 Turbo",
            request: GenerationRequest(prompt: prompt, negativePrompt: "blurry", width: 4, height: 2, steps: 8, cfg: 1.5,
                                       sampler: "euler", sigmas: [1, 0], seed: 1234),
            durationSeconds: 12.5
        )
    }

    @Test func savedImagesCarryTheirSettings() throws {
        let saved = try store.save(image(), record: record())

        #expect(saved.url.pathExtension == "png")
        #expect(ImageCodec.record(in: saved.url) == record(prompt: "a red fox").withID(saved.record.id))
    }

    @Test func pixelsSurviveTheRoundTrip() throws {
        let original = image()
        let saved = try store.save(original, record: record())

        let source = try #require(CGImageSourceCreateWithURL(saved.url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 4)
        #expect(decoded.height == 2)
        let bytes = try #require(decoded.dataProvider?.data as Data?)
        // Compare per pixel: rows may be padded and RGB may be stored with a filler byte.
        let bytesPerPixel = decoded.bitsPerPixel / 8
        for y in 0..<2 {
            for x in 0..<4 {
                let got = bytes.subdata(in: (y * decoded.bytesPerRow + x * bytesPerPixel)..<(y * decoded.bytesPerRow + x * bytesPerPixel + 3))
                let want = original.pixels.subdata(in: ((y * 4 + x) * 3)..<((y * 4 + x) * 3 + 3))
                #expect(got == want, "pixel \(x),\(y)")
            }
        }
    }

    @Test func descriptionIsReadableByOtherTools() throws {
        let saved = try store.save(image(), record: record())

        #expect(PNGText.entries(in: saved.url)["parameters"] == """
        a red fox
        Negative prompt: blurry
        Steps: 8, Sampler: euler, CFG scale: 1.5, Seed: 1234, Size: 4x2, Model: Qwen-Image 2.1 Turbo
        """)
    }

    @Test func textChunksKeepNonASCIIAndHaveValidChecksums() throws {
        let saved = try store.save(image(), record: record(prompt: "caf\u{E9} \u{1F98A} \u{732B}"))

        #expect(ImageCodec.record(in: saved.url)?.request.prompt == "caf\u{E9} \u{1F98A} \u{732B}")
        // ImageIO rejects PNG files with a bad chunk CRC, so decoding proves the checksums.
        let source = try #require(CGImageSourceCreateWithURL(saved.url as CFURL, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
        // CRC-32 check value from the PNG specification's reference algorithm.
        #expect(PNGText.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func supportsImagesWithAlpha() throws {
        let saved = try store.save(image(channels: 4), record: record())

        let source = try #require(CGImageSourceCreateWithURL(saved.url as CFURL, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.alphaInfo != .none && decoded.alphaInfo != .noneSkipLast && decoded.alphaInfo != .noneSkipFirst)
    }

    @Test func rejectsPixelDataOfTheWrongLength() {
        let broken = GeneratedImage(width: 4, height: 4, channels: 3, pixels: Data(count: 5))
        #expect(throws: ImageCodecError.self) { try ImageCodec.pngData(for: broken, record: record()) }
    }

    @Test func listsNewestFirstAndIgnoresForeignFiles() throws {
        let old = try store.save(image(), record: record(prompt: "old", createdAt: Date(timeIntervalSince1970: 1_000)))
        let new = try store.save(image(), record: record(prompt: "new", createdAt: Date(timeIntervalSince1970: 2_000)))
        try Data("not a png".utf8).write(to: store.directory.appendingPathComponent("notes.txt"))
        try Data("not a png".utf8).write(to: store.directory.appendingPathComponent("broken.png"))

        #expect(store.items().map(\.record.request.prompt) == ["new", "old"])

        try store.delete(new)
        #expect(store.items().map(\.id) == [old.id])
    }

    @Test func emptyGalleryHasNoItems() {
        #expect(store.items().isEmpty)
    }
}

private extension GenerationRecord {
    func withID(_ id: UUID) -> GenerationRecord {
        var copy = self
        copy.id = id
        return copy
    }
}

import Foundation
import Testing
@testable import KilnCore

@Suite struct AttachmentLibraryTests {
    private let files: FileFixtures
    private let library: AttachmentLibrary

    init() throws {
        files = try FileFixtures()
        library = AttachmentLibrary(directory: files.root.appendingPathComponent("attachments"))
    }

    @Test func anImageIsCopiedUnderAnIdOfItsOwn() throws {
        let original = try files.image()
        let copy = try library.add(original, accepting: [.image])

        #expect(copy.deletingLastPathComponent().path == library.directory.path)
        #expect(copy.pathExtension == "png")
        #expect(UUID(uuidString: copy.deletingPathExtension().lastPathComponent) != nil)
        #expect(try Data(contentsOf: copy) == Data(contentsOf: original))
        #expect(library.url(named: copy.lastPathComponent) == copy)
    }

    @Test func anImageWithoutAnExtensionIsStillAnImage() throws {
        let copy = try library.add(try files.image(named: "picture"), accepting: [.image])
        #expect(copy.pathExtension == "png")
    }

    @Test func anotherKindOfFileKeepsItsNameAfterTheId() throws {
        let copy = try library.add(try files.file(named: "My Talk.MP3"), accepting: [.image, .audio])
        #expect(copy.lastPathComponent.hasSuffix("-My Talk.mp3"))
        #expect(AttachmentLibrary.displayName(of: copy) == "My Talk.mp3")
    }

    @Test func aFileOfTheWrongKindIsRefusedInPlainWords() throws {
        let notAnImage = try files.file(named: "notes.png")
        #expect(throws: AttachmentLibrary.ImportError.notAccepted([.image])) {
            try library.add(notAnImage, accepting: [.image])
        }
        #expect(!FileManager.default.fileExists(atPath: library.directory.path))

        typealias Refused = AttachmentLibrary.ImportError
        #expect(Refused.notAccepted([]).errorDescription == "This model does not take attachments.")
        #expect(Refused.notAccepted([.image]).errorDescription == "That file is not an image Kiln can read. Try a PNG or JPEG.")
        #expect(Refused.notAccepted([.audio, .text]).errorDescription
            == "This model takes audio or text files, and that file is not one Kiln can read.")
    }

    @Test func aFilesKindIsReadFromItsType() {
        #expect(AttachmentLibrary.kind(of: URL(fileURLWithPath: "/a.jpeg")) == .image)
        #expect(AttachmentLibrary.kind(of: URL(fileURLWithPath: "/a.wav")) == .audio)
        #expect(AttachmentLibrary.kind(of: URL(fileURLWithPath: "/a.txt")) == .text)
        #expect(AttachmentLibrary.kind(of: URL(fileURLWithPath: "/a.zip")) == nil)
    }

    @Test func aNameWithoutAnIdIsShownAsItIs() {
        #expect(AttachmentLibrary.displayName(of: URL(fileURLWithPath: "/x/talk.mp3")) == "talk.mp3")
        // An image's copy is its id alone.
        let id = UUID().uuidString
        #expect(AttachmentLibrary.displayName(of: URL(fileURLWithPath: "/x/\(id).png")) == "\(id).png")
    }
}

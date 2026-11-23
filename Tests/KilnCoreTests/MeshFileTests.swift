import Foundation
import Testing
@testable import KilnCore

/// Reading the surface out of a GLB file.
@Suite struct MeshFileTests {
    @Test func aTexturedSurfaceIsReadInFull() throws {
        let mesh = try MeshFile(glb: GLBFixture.square())

        #expect(mesh.vertexCount == 4)
        #expect(mesh.triangleCount == 2)
        #expect(mesh.positions == GLBFixture.floats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0]))
        #expect(mesh.normals?.count == 48)
        #expect(mesh.textureCoordinates?.count == 32)
        #expect(mesh.baseColorImage == Data("colour image".utf8))
        #expect(mesh.metallicRoughnessImage == Data("rough image".utf8))
        #expect(mesh.lowerBound == [0, 0, 0])
        #expect(mesh.upperBound == [1, 1, 0])
    }

    @Test func sixteenBitCornersAreWidened() throws {
        let narrow = try MeshFile(glb: GLBFixture.square(indexType: 5123))
        #expect(narrow.indices == (try MeshFile(glb: GLBFixture.square())).indices)
        #expect(narrow.triangleCount == 2)
    }

    @Test func aSurfaceWithoutTextureHasNoImages() throws {
        let mesh = try MeshFile(glb: GLBFixture.square(textured: false))
        #expect(mesh.baseColorImage == nil && mesh.metallicRoughnessImage == nil)
        #expect(mesh.triangleCount == 2)
    }

    @Test func aFileThatIsNotGLBIsRefused() {
        #expect(!MeshFile.isGLB(Data("not a model".utf8)))
        #expect(throws: MeshFileError.notGLB) { try MeshFile(glb: Data("glTF but far too short".utf8.prefix(8))) }
        #expect(throws: MeshFileError.notGLB) { try MeshFile(glb: Data("glTF".utf8) + Data(repeating: 0xFF, count: 40)) }
    }

    @Test func aFileCutShortIsRefusedInsteadOfReadPastItsEnd() {
        let whole = GLBFixture.square()
        for length in stride(from: 20, to: whole.count, by: 37) {
            #expect(throws: MeshFileError.self) { try MeshFile(glb: whole.prefix(length)) }
        }
    }

    @Test func aTriangleNamingAMissingCornerIsRefused() {
        // Four corners, and a triangle that asks for the ninth.
        var json = try! JSONSerialization.jsonObject(with: Self.description(of: GLBFixture.square())) as! [String: Any]
        var accessors = json["accessors"] as! [[String: Any]]
        accessors[0]["count"] = 2
        accessors[1]["count"] = 2
        accessors[2]["count"] = 2
        json["accessors"] = accessors
        let glb = GLBFixture.assemble(json: json, binary: Self.binary(of: GLBFixture.square()))
        #expect(throws: MeshFileError.unsupported("a triangle names a corner that does not exist")) { try MeshFile(glb: glb) }
    }

    @Test func aViewPointingOutsideTheDataIsRefused() {
        var json = try! JSONSerialization.jsonObject(with: Self.description(of: GLBFixture.square())) as! [String: Any]
        var views = json["bufferViews"] as! [[String: Any]]
        views[0]["byteOffset"] = 1_000_000
        json["bufferViews"] = views
        let glb = GLBFixture.assemble(json: json, binary: Self.binary(of: GLBFixture.square()))
        #expect(throws: MeshFileError.unsupported("its data is cut short")) { try MeshFile(glb: glb) }
    }

    @Test func everyErrorSaysWhatIsWrongInPlainWords() {
        #expect(MeshFileError.notGLB.errorDescription == "The file is not a 3D object Kiln can read.")
        #expect(MeshFileError.unsupported("it holds no surface").errorDescription == "The 3D object could not be read: it holds no surface.")
    }

    private static func description(of glb: Data) -> Data {
        let length = Int(glb.subdata(in: 12..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        return glb.subdata(in: 20..<20 + length)
    }

    private static func binary(of glb: Data) -> Data {
        let length = Int(glb.subdata(in: 12..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        return glb.subdata(in: (28 + length)..<glb.count)
    }
}

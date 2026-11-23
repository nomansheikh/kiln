import Foundation
import Testing
@testable import KilnCore

@Suite struct GLBUprightTests {
    private func values(_ data: Data?) -> [Float] {
        guard let data else { return [] }
        return data.withUnsafeBytes { raw in
            stride(from: 0, to: raw.count, by: 4).map { raw.loadUnaligned(fromByteOffset: $0, as: Float.self) }
        }
    }

    @Test func everyPointAndNormalIsTurnedAQuarterAboutX() throws {
        let turned = try MeshFile(glb: GLBUpright.turned(GLBFixture.square()))
        // (x, y, z) becomes (x, -z, y): a square standing in x and y now lies in x and z.
        #expect(values(turned.positions) == [0, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1])
        #expect(values(turned.normals) == [0, -1, 0, 0, -1, 0, 0, -1, 0, 0, -1, 0])
    }

    @Test func theStatedBoundsFollowThePoints() throws {
        let turned = try MeshFile(glb: GLBUpright.turned(GLBFixture.square()))
        #expect(turned.lowerBound == [0, 0, 0])
        #expect(turned.upperBound == [1, 0, 1])
    }

    @Test func trianglesTexturePositionsAndImagesAreKept() throws {
        let before = try MeshFile(glb: GLBFixture.square())
        let after = try MeshFile(glb: GLBUpright.turned(GLBFixture.square()))
        #expect(after.indices == before.indices)
        #expect(after.textureCoordinates == before.textureCoordinates)
        #expect(after.baseColorImage == before.baseColorImage)
        #expect(after.metallicRoughnessImage == before.metallicRoughnessImage)
    }

    @Test func fourTurnsGiveBackTheSamePoints() throws {
        var glb = GLBFixture.square()
        for _ in 0..<4 { glb = try GLBUpright.turned(glb) }
        #expect(try MeshFile(glb: glb).positions == MeshFile(glb: GLBFixture.square()).positions)
    }

    @Test func aFileThatIsNotGLBIsRefused() {
        #expect(throws: MeshFileError.notGLB) { try GLBUpright.turned(Data("not a model".utf8)) }
    }

    @Test func pointsCutShortAreRefused() {
        var json = try! JSONSerialization.jsonObject(with: Data(#"{"asset":{"version":"2.0"}}"#.utf8)) as! [String: Any]
        json["bufferViews"] = [["buffer": 0, "byteOffset": 0, "byteLength": 12]]
        json["accessors"] = [["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3"]]
        json["meshes"] = [["primitives": [["attributes": ["POSITION": 0]]]]]
        let glb = GLBFixture.assemble(json: json, binary: GLBFixture.floats([0, 0, 0]))
        #expect(throws: MeshFileError.self) { try GLBUpright.turned(glb) }
    }
}

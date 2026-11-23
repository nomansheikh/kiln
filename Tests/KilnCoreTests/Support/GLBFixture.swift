import Foundation
@testable import KilnCore

/// Builds small GLB files by hand: one triangle, or two that share an edge.
enum GLBFixture {
    static func floats(_ values: [Float]) -> Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// A square of two triangles with normals, texture positions and two images.
    /// `indexType` is 5125 for 32-bit corners or 5123 for 16-bit ones.
    static func square(indexType: Int = 5125, textured: Bool = true) -> Data {
        let positions = floats([0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0])
        let normals = floats([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1])
        let coordinates = floats([0, 0, 1, 0, 1, 1, 0, 1])
        let corners: [UInt32] = [0, 1, 2, 0, 2, 3]
        let indices = indexType == 5125
            ? corners.withUnsafeBufferPointer { Data(buffer: $0) }
            : corners.map(UInt16.init).withUnsafeBufferPointer { Data(buffer: $0) }
        var parts = [positions, normals, coordinates, indices]
        if textured { parts += [Data("colour image".utf8), Data("rough image".utf8)] }

        var views: [[String: Any]] = []
        var binary = Data()
        for part in parts {
            views.append(["buffer": 0, "byteOffset": binary.count, "byteLength": part.count])
            binary.append(part)
            while binary.count % 4 != 0 { binary.append(0) }
        }
        var json: [String: Any] = [
            "asset": ["version": "2.0"],
            "buffers": [["byteLength": binary.count]],
            "bufferViews": views,
            "accessors": [
                ["bufferView": 0, "componentType": 5126, "count": 4, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]],
                ["bufferView": 1, "componentType": 5126, "count": 4, "type": "VEC3"],
                ["bufferView": 2, "componentType": 5126, "count": 4, "type": "VEC2"],
                ["bufferView": 3, "componentType": indexType, "count": 6, "type": "SCALAR"],
            ],
            "meshes": [["primitives": [["attributes": ["POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2], "indices": 3, "material": 0, "mode": 4]]]],
        ]
        if textured {
            json["materials"] = [["pbrMetallicRoughness": ["baseColorTexture": ["index": 0], "metallicRoughnessTexture": ["index": 1]]]]
            json["textures"] = [["source": 0], ["source": 1]]
            json["images"] = [["bufferView": 4, "mimeType": "image/png"], ["bufferView": 5, "mimeType": "image/png"]]
        } else {
            json["materials"] = [[String: Any]()]
        }
        return assemble(json: json, binary: binary)
    }

    /// Wraps a description and its bytes as a GLB file.
    static func assemble(json: [String: Any], binary: Data) -> Data {
        var text = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        while text.count % 4 != 0 { text.append(0x20) }
        func word(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
        var file = Data("glTF".utf8) + word(2) + word(12 + 8 + text.count + 8 + binary.count)
        file += word(text.count) + Data("JSON".utf8) + text
        file += word(binary.count) + Data("BIN\0".utf8) + binary
        return file
    }
}

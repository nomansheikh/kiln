import Foundation

/// Stands a Pixal3D object up. trellis.cpp 0.8.1 writes every object as if it
/// were TRELLIS.2's, whose grid has another axis pointing up, so a Pixal3D
/// object comes out lying on its back. The engine corrects that after 0.8.1
/// (pwilkin/trellis.cpp#58): remove this when `Vendor/trellis.cpp` moves past it.
enum GLBUpright {
    /// The file with every point and normal turned a quarter about the x axis:
    /// (x, y, z) becomes (x, -z, y). Winding, texture positions and images are unchanged.
    static func turned(_ glb: Data) throws(MeshFileError) -> Data {
        guard MeshFile.isGLB(glb) else { throw .notGLB }
        let data = Data(glb)
        let jsonLength = uint32(data, at: 12)
        let jsonEnd = 20 + jsonLength
        guard jsonEnd + 8 <= data.count,
              var json = (try? JSONSerialization.jsonObject(with: data.subdata(in: 20..<jsonEnd))) as? [String: Any],
              var accessors = json["accessors"] as? [[String: Any]],
              let views = json["bufferViews"] as? [[String: Any]],
              let meshes = json["meshes"] as? [[String: Any]]
        else { throw .notGLB }
        let binaryLength = uint32(data, at: jsonEnd)
        guard jsonEnd + 8 + binaryLength <= data.count else { throw .unsupported("its data is cut short") }
        var binary = data.subdata(in: (jsonEnd + 8)..<(jsonEnd + 8 + binaryLength))

        var points = Set<Int>()
        var directions = Set<Int>()
        for mesh in meshes {
            for primitive in mesh["primitives"] as? [[String: Any]] ?? [] {
                let attributes = primitive["attributes"] as? [String: Int] ?? [:]
                if let index = attributes["POSITION"] { points.insert(index) }
                if let index = attributes["NORMAL"] { directions.insert(index) }
            }
        }
        for index in points.union(directions) {
            guard accessors.indices.contains(index) else { throw .unsupported("it names data that is missing") }
            try turn(accessors[index], views: views, in: &binary)
        }
        for index in points {
            if let low = floats(accessors[index]["min"]), let high = floats(accessors[index]["max"]) {
                accessors[index]["min"] = [low[0], -high[2], low[1]]
                accessors[index]["max"] = [high[0], -low[2], high[1]]
            }
        }
        json["accessors"] = accessors
        return try assemble(json: json, binary: binary)
    }

    private static func turn(_ accessor: [String: Any], views: [[String: Any]], in binary: inout Data) throws(MeshFileError) {
        guard accessor["componentType"] as? Int == 5126, accessor["type"] as? String == "VEC3",
              let count = accessor["count"] as? Int, let viewIndex = accessor["bufferView"] as? Int,
              views.indices.contains(viewIndex), let length = views[viewIndex]["byteLength"] as? Int, length >= 0
        else { throw .unsupported("its numbers are in a form Kiln does not read") }
        let view = views[viewIndex]
        let viewStart = view["byteOffset"] as? Int ?? 0
        let offset = accessor["byteOffset"] as? Int ?? 0
        let stride = view["byteStride"] as? Int ?? 12
        guard count >= 0, viewStart >= 0, offset >= 0, stride >= 12, viewStart + length <= binary.count,
              count == 0 || offset + (count - 1) * stride + 12 <= length
        else { throw .unsupported("its data is cut short") }
        let start = viewStart + offset
        binary.withUnsafeMutableBytes { raw in
            for element in 0..<count {
                let at = start + element * stride
                let y = raw.loadUnaligned(fromByteOffset: at + 4, as: Float.self)
                let z = raw.loadUnaligned(fromByteOffset: at + 8, as: Float.self)
                raw.storeBytes(of: -z, toByteOffset: at + 4, as: Float.self)
                raw.storeBytes(of: y, toByteOffset: at + 8, as: Float.self)
            }
        }
    }

    private static func assemble(json: [String: Any], binary: Data) throws(MeshFileError) -> Data {
        guard var text = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else { throw .notGLB }
        // Each part is a whole number of four-byte words, the description padded with spaces.
        while text.count % 4 != 0 { text.append(0x20) }
        var file = Data("glTF".utf8) + word(2) + word(12 + 8 + text.count + 8 + binary.count)
        file += word(text.count) + Data("JSON".utf8) + text
        file += word(binary.count) + Data("BIN\0".utf8) + binary
        return file
    }

    private static func floats(_ value: Any?) -> [Float]? {
        guard let numbers = value as? [NSNumber], numbers.count == 3 else { return nil }
        return numbers.map(\.floatValue)
    }

    private static func word(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
    }

    private static func uint32(_ data: Data, at offset: Int) -> Int {
        Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }
}

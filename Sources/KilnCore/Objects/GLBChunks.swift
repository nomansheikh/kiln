import Foundation

/// The two parts of a GLB file, a JSON description and a block of bytes, with
/// checked access to the arrays the description names.
struct GLBChunks {
    struct Document: Decodable {
        struct Mesh: Decodable { var primitives: [Primitive] }
        struct Primitive: Decodable {
            var attributes: [String: Int]
            var indices: Int?
            var material: Int?
            var mode: Int?
        }
        struct Accessor: Decodable {
            var bufferView: Int?
            var byteOffset: Int?
            var componentType: Int
            var count: Int
            var type: String
            var min: [Float]?
            var max: [Float]?
        }
        struct BufferView: Decodable {
            var byteOffset: Int?
            var byteLength: Int
            var byteStride: Int?
        }
        struct TextureRef: Decodable { var index: Int }
        struct PBR: Decodable {
            var baseColorTexture: TextureRef?
            var metallicRoughnessTexture: TextureRef?
        }
        struct Material: Decodable { var pbrMetallicRoughness: PBR? }
        struct Texture: Decodable { var source: Int? }
        struct Image: Decodable { var bufferView: Int? }

        var meshes: [Mesh]?
        var accessors: [Accessor]
        var bufferViews: [BufferView]
        var materials: [Material]?
        var textures: [Texture]?
        var images: [Image]?
    }

    let json: Document
    private let binary: Data

    init(_ glb: Data) throws(MeshFileError) {
        guard MeshFile.isGLB(glb) else { throw .notGLB }
        let data = Data(glb)
        let jsonLength = Self.uint32(data, at: 12)
        let jsonEnd = 20 + jsonLength
        guard Self.uint32(data, at: 8) <= data.count, jsonEnd <= data.count,
              let document = try? JSONDecoder().decode(Document.self, from: data.subdata(in: 20..<jsonEnd))
        else { throw .notGLB }
        json = document
        // The bytes follow in a chunk of their own, after its length and its type.
        guard jsonEnd + 8 <= data.count else { throw .unsupported("it holds no data") }
        let binaryLength = Self.uint32(data, at: jsonEnd)
        guard jsonEnd + 8 + binaryLength <= data.count else { throw .unsupported("its data is cut short") }
        binary = data.subdata(in: (jsonEnd + 8)..<(jsonEnd + 8 + binaryLength))
    }

    private static func uint32(_ data: Data, at offset: Int) -> Int {
        Int(data.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }

    /// The bytes one view covers.
    private func bytes(view index: Int) throws(MeshFileError) -> (data: Data, stride: Int?) {
        guard let view = json.bufferViews[safe: index] else { throw .unsupported("it names data that is missing") }
        let start = view.byteOffset ?? 0
        guard start >= 0, view.byteLength >= 0, start + view.byteLength <= binary.count else {
            throw .unsupported("its data is cut short")
        }
        return (binary.subdata(in: start..<start + view.byteLength), view.byteStride)
    }

    /// The elements of an accessor, packed one after the other.
    private func elements(accessor index: Int, size: Int) throws(MeshFileError) -> Data {
        guard let accessor = json.accessors[safe: index], let viewIndex = accessor.bufferView, accessor.count >= 0 else {
            throw .unsupported("it names data that is missing")
        }
        let view = try bytes(view: viewIndex)
        let offset = accessor.byteOffset ?? 0
        let stride = view.stride ?? size
        guard offset >= 0, stride >= size, accessor.count == 0 || offset + (accessor.count - 1) * stride + size <= view.data.count else {
            throw .unsupported("its data is cut short")
        }
        if stride == size {
            return view.data.subdata(in: offset..<offset + accessor.count * size)
        }
        var packed = Data(capacity: accessor.count * size)
        for element in 0..<accessor.count {
            packed.append(view.data.subdata(in: (offset + element * stride)..<(offset + element * stride + size)))
        }
        return packed
    }

    func floats(accessor index: Int, components: Int) throws(MeshFileError) -> Data {
        guard let accessor = json.accessors[safe: index], accessor.componentType == 5126,
              accessor.type == (components == 3 ? "VEC3" : "VEC2")
        else { throw .unsupported("its numbers are in a form Kiln does not read") }
        return try elements(accessor: index, size: 4 * components)
    }

    /// Triangle corners as 32-bit integers, whatever width the file stores them in.
    func indices(accessor index: Int) throws(MeshFileError) -> Data {
        guard let accessor = json.accessors[safe: index], accessor.type == "SCALAR" else {
            throw .unsupported("its triangles are in a form Kiln does not read")
        }
        switch accessor.componentType {
        case 5125:
            return try elements(accessor: index, size: 4)
        case 5123:
            let narrow = try elements(accessor: index, size: 2)
            var wide = Data(capacity: narrow.count * 2)
            narrow.withUnsafeBytes { raw in
                for position in stride(from: 0, to: raw.count, by: 2) {
                    var value = UInt32(raw.loadUnaligned(fromByteOffset: position, as: UInt16.self))
                    withUnsafeBytes(of: &value) { wide.append(contentsOf: $0) }
                }
            }
            return wide
        default:
            throw .unsupported("its triangles are in a form Kiln does not read")
        }
    }

    func largestIndex(in indices: Data) -> Int {
        indices.withUnsafeBytes { raw in
            var largest: UInt32 = 0
            for position in stride(from: 0, to: raw.count - 3, by: 4) {
                largest = max(largest, raw.loadUnaligned(fromByteOffset: position, as: UInt32.self))
            }
            return Int(largest)
        }
    }

    /// The image file a texture points at, or nil when it is kept outside the GLB.
    func image(texture index: Int) throws(MeshFileError) -> Data? {
        guard let source = json.textures?[safe: index]?.source, let view = json.images?[safe: source]?.bufferView else { return nil }
        return try bytes(view: view).data
    }
}

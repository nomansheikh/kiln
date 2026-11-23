import Foundation

public enum MeshFileError: Error, Equatable, LocalizedError {
    case notGLB
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notGLB: "The file is not a 3D object Kiln can read."
        case .unsupported(let what): "The 3D object could not be read: \(what)."
        }
    }
}

/// The surface inside a GLB file, as plain arrays a renderer or an exporter can
/// use. macOS cannot read GLB itself.
///
/// It reads what Kiln's engine writes: one surface of triangles, with a normal
/// and a texture position per corner and its colours as images inside the
/// file. Every offset is checked, since the file comes from a helper process.
public struct MeshFile: Sendable, Equatable {
    /// Three 32-bit floats per corner: x, y, z.
    public var positions: Data
    /// Three 32-bit floats per corner, or nil when the file has none.
    public var normals: Data?
    /// Two 32-bit floats per corner, or nil when the surface has no texture.
    public var textureCoordinates: Data?
    /// Three 32-bit unsigned integers per triangle.
    public var indices: Data
    /// The surface's colour, as an image file's bytes (PNG or JPEG).
    public var baseColorImage: Data?
    /// Roughness in the green channel and metalness in the blue, as glTF defines it.
    public var metallicRoughnessImage: Data?
    /// The smallest and largest x, y and z, as the file states them.
    public var lowerBound: [Float]
    public var upperBound: [Float]

    public var vertexCount: Int { positions.count / 12 }
    public var triangleCount: Int { indices.count / 12 }

    public static func isGLB(_ data: Data) -> Bool {
        data.count >= 20 && data.prefix(4) == Data("glTF".utf8)
    }

    public init(glb: Data) throws(MeshFileError) {
        let chunks = try GLBChunks(glb)
        guard let primitive = chunks.json.meshes?.first?.primitives.first else { throw .unsupported("it holds no surface") }
        guard primitive.mode ?? 4 == 4 else { throw .unsupported("its surface is not made of triangles") }
        guard let position = primitive.attributes["POSITION"], let index = primitive.indices else {
            throw .unsupported("its surface has no corners or no triangles")
        }

        positions = try chunks.floats(accessor: position, components: 3)
        if let normal = primitive.attributes["NORMAL"] {
            normals = try chunks.floats(accessor: normal, components: 3)
        }
        if let coordinate = primitive.attributes["TEXCOORD_0"] {
            textureCoordinates = try chunks.floats(accessor: coordinate, components: 2)
        }
        indices = try chunks.indices(accessor: index)
        let count = positions.count / 12
        guard normals.map({ $0.count == count * 12 }) ?? true, textureCoordinates.map({ $0.count == count * 8 }) ?? true else {
            throw .unsupported("its corners do not line up")
        }
        guard indices.count % 12 == 0, chunks.largestIndex(in: indices) < count else {
            throw .unsupported("a triangle names a corner that does not exist")
        }

        let material = primitive.material.flatMap { chunks.json.materials?[safe: $0] }?.pbrMetallicRoughness
        if let texture = material?.baseColorTexture {
            baseColorImage = try chunks.image(texture: texture.index)
        }
        if let texture = material?.metallicRoughnessTexture {
            metallicRoughnessImage = try chunks.image(texture: texture.index)
        }
        let stated = chunks.json.accessors[safe: position]
        lowerBound = stated?.min?.count == 3 ? stated?.min ?? [] : [-0.5, -0.5, -0.5]
        upperBound = stated?.max?.count == 3 ? stated?.max ?? [] : [0.5, 0.5, 0.5]
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

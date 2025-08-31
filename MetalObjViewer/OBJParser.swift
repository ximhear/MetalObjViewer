import Foundation
import simd

struct Vertex {
    var position: simd_float3
    var normal: simd_float3
    var texCoord: simd_float2
}

struct Face {
    var vertices: [Int]
    var normals: [Int]
    var texCoords: [Int]
}

class OBJParser {
    private var positions: [simd_float3] = []
    private var normals: [simd_float3] = []
    private var texCoords: [simd_float2] = []
    private var faces: [Face] = []
    private var smoothGroups: [Int: Int] = [:]
    
    func parseOBJ(from url: URL) throws -> [Vertex] {
        let content = try String(contentsOf: url)
        let lines = content.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.isEmpty || trimmedLine.hasPrefix("#") {
                continue
            }
            
            let components = trimmedLine.components(separatedBy: .whitespaces)
            guard !components.isEmpty else { continue }
            
            switch components[0] {
            case "v":
                parseVertex(components)
            case "vn":
                parseNormal(components)
            case "vt":
                parseTexCoord(components)
            case "f":
                parseFace(components)
            case "s":
                parseSmoothGroup(components)
            default:
                break
            }
        }
        
        return generateVertices()
    }
    
    private func parseVertex(_ components: [String]) {
        guard components.count >= 4 else { return }
        
        let x = Float(components[1]) ?? 0.0
        let y = Float(components[2]) ?? 0.0
        let z = Float(components[3]) ?? 0.0
        
        positions.append(simd_float3(x, y, z))
    }
    
    private func parseNormal(_ components: [String]) {
        guard components.count >= 4 else { return }
        
        let x = Float(components[1]) ?? 0.0
        let y = Float(components[2]) ?? 0.0
        let z = Float(components[3]) ?? 0.0
        
        normals.append(simd_float3(x, y, z))
    }
    
    private func parseTexCoord(_ components: [String]) {
        guard components.count >= 3 else { return }
        
        let u = Float(components[1]) ?? 0.0
        let v = Float(components[2]) ?? 0.0
        
        texCoords.append(simd_float2(u, v))
    }
    
    private func parseFace(_ components: [String]) {
        guard components.count >= 4 else { return }
        
        var faceVertices: [Int] = []
        var faceNormals: [Int] = []
        var faceTexCoords: [Int] = []
        
        for i in 1..<components.count {
            let indices = components[i].components(separatedBy: "/")
            
            if let vertexIndex = Int(indices[0]) {
                faceVertices.append(vertexIndex - 1)
            }
            
            if indices.count > 1 && !indices[1].isEmpty {
                if let texIndex = Int(indices[1]) {
                    faceTexCoords.append(texIndex - 1)
                }
            }
            
            if indices.count > 2 && !indices[2].isEmpty {
                if let normalIndex = Int(indices[2]) {
                    faceNormals.append(normalIndex - 1)
                }
            }
        }
        
        let face = Face(vertices: faceVertices, normals: faceNormals, texCoords: faceTexCoords)
        faces.append(face)
    }
    
    private func parseSmoothGroup(_ components: [String]) {
        guard components.count >= 2 else { return }
        
        if let groupId = Int(components[1]) {
            smoothGroups[faces.count] = groupId
        }
    }
    
    private func generateVertices() -> [Vertex] {
        var vertices: [Vertex] = []
        
        for face in faces {
            let faceVertexCount = face.vertices.count
            
            if faceVertexCount == 3 {
                // Triangle - add as is
                for i in 0..<3 {
                    let vertex = createVertex(face: face, index: i)
                    vertices.append(vertex)
                }
            } else if faceVertexCount == 4 {
                // Quad - triangulate with clockwise winding for left-handed system
                // First triangle: 0,1,2 - Second triangle: 0,2,3
                let indices = [0, 1, 2, 0, 2, 3]
                for index in indices {
                    let vertex = createVertex(face: face, index: index)
                    vertices.append(vertex)
                }
            } else if faceVertexCount > 4 {
                // Polygon - fan triangulation from vertex 0
                for i in 1..<faceVertexCount-1 {
                    let indices = [0, i, i+1]
                    for index in indices {
                        let vertex = createVertex(face: face, index: index)
                        vertices.append(vertex)
                    }
                }
            }
        }
        
        return vertices
    }
    
    private func createVertex(face: Face, index: Int) -> Vertex {
        let posIndex = face.vertices[index]
        let position = positions[posIndex]
        
        var normal = simd_float3(0, 1, 0)
        if index < face.normals.count && face.normals[index] < normals.count {
            normal = normals[face.normals[index]]
        }
        
        var texCoord = simd_float2(0, 0)
        if index < face.texCoords.count && face.texCoords[index] < texCoords.count {
            texCoord = texCoords[face.texCoords[index]]
        }
        
        return Vertex(position: position, normal: normal, texCoord: texCoord)
    }
}
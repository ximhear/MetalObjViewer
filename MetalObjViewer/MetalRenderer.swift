import Metal
import MetalKit
import simd

struct Uniforms {
    var modelMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4
    var normalMatrix: simd_float3x3
    var lightDirection: simd_float3
    var lightColor: simd_float3
}

struct RenderObject {
    var vertices: [Vertex]
    var vertexBuffer: MTLBuffer?
    var uniformBuffer: MTLBuffer?  // Each object has its own uniform buffer
    var rotation: simd_quatf
    var translation: simd_float3
    var name: String
    
    init(vertices: [Vertex], name: String, device: MTLDevice) {
        self.vertices = vertices
        self.name = name
        self.rotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))
        self.translation = simd_float3(0, 0, 0)
        
        if !vertices.isEmpty {
            self.vertexBuffer = device.makeBuffer(bytes: vertices,
                                                length: vertices.count * MemoryLayout<Vertex>.stride,
                                                options: [])
            // Vertex buffer created successfully
        } else {
            print("Warning: No vertices for \(name)")
        }
        
        // Create separate uniform buffer for this object
        self.uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride, options: [])
    }
}

class MetalRenderer: NSObject, MTKViewDelegate {
    private var device: MTLDevice
    private var commandQueue: MTLCommandQueue
    private var renderPipelineState: MTLRenderPipelineState?
    private var depthStencilState: MTLDepthStencilState?
    // uniformBuffer removed - now each object has its own
    
    // Multiple objects support
    private var renderObjects: [RenderObject] = []
    
    private var viewMatrix = matrix_identity_float4x4
    private var projectionMatrix = matrix_identity_float4x4
    
    // Camera orbit rotation (for world rotation effect)  
    private var cameraRadius: Float = 5.0  // Close distance for overlapping objects
    private var cameraRotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))  // Identity quaternion
    
    // Debug frame counter
    private var debugFrameCount = 0
    
    // Trackball parameters - no longer needed for simple axis rotation
    
    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        super.init()
        setupRenderPipeline()
    }
    
    private func setupRenderPipeline() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library")
        }
        
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<simd_float3>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0
        
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<simd_float3>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0
        
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        do {
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
        
        setupDepthStencilState()
        
        // No global uniform buffer needed - each object has its own
    }
    
    private func setupDepthStencilState() {
        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        depthStencilDescriptor.isDepthWriteEnabled = true
        
        depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor)
    }
    
    func loadModel(vertices: [Vertex]) {
        print("LoadModel called with \(vertices.count) vertices")
        
        // Create first object
        let object = RenderObject(vertices: Array(vertices), name: "Object_\(renderObjects.count)", device: device)
        renderObjects.append(object)
        
        // Add second object at different position for testing
        var secondObject = RenderObject(vertices: Array(vertices), name: "Object_\(renderObjects.count)", device: device)
        secondObject.translation = simd_float3(0.5, 0.0, 0)  // Right and slightly up
        renderObjects.append(secondObject)
        
        // Add third object for better visibility
        var thirdObject = RenderObject(vertices: Array(vertices), name: "Object_\(renderObjects.count)", device: device)
        thirdObject.translation = simd_float3(-0.5, -0.0, 0.0)  // Left, down, and slightly forward
        renderObjects.append(thirdObject)
        
        print("Created \(renderObjects.count) objects total")
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = simd_float4x4(perspectiveProjectionFov: Float.pi / 4,
                                       aspectRatio: aspect,
                                       nearZ: 0.1,
                                       farZ: 100.0)
    }
    
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let renderPipelineState = renderPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        updateViewMatrix()
        
        renderEncoder.setRenderPipelineState(renderPipelineState)
        
        // Set depth stencil state for depth testing
        if let depthStencilState = depthStencilState {
            renderEncoder.setDepthStencilState(depthStencilState)
        }
        
        // Left-handed coordinate system: cull back faces with clockwise winding
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.clockwise)
        
        // Render each object with its own transform and uniform buffer
        for (index, object) in renderObjects.enumerated() {
            guard let vertexBuffer = object.vertexBuffer, 
                  let objectUniformBuffer = object.uniformBuffer,
                  !object.vertices.isEmpty else { 
                print("Skipping object \(index): missing buffer or empty vertices")
                continue 
            }
            
            // Update uniforms for this specific object in its own buffer
            updateUniforms(for: object)
            
            // Set buffers for this object - use object's own uniform buffer
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(objectUniformBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentBuffer(objectUniformBuffer, offset: 0, index: 0)
            
            // Draw this object
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: object.vertices.count)
        }
        
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    private func updateViewMatrix() {
        // Camera orbits around world center using quaternion rotation
        // First apply rotation, then translate by radius
        let rotationMatrix = simd_float4x4(cameraRotation)
        
        // Initial camera position (before rotation) - looking down the Z axis
        let initialPosition = simd_float3(0, 0, cameraRadius)
        
        // Rotate the camera position around the origin
        let rotatedPosition = rotationMatrix * simd_float4(initialPosition, 1.0)
        let eye = simd_float3(rotatedPosition.x, rotatedPosition.y, rotatedPosition.z)
        
        // Also rotate the up vector to maintain proper orientation
        let initialUp = simd_float3(0, 1, 0)
        let rotatedUp = rotationMatrix * simd_float4(initialUp, 0.0)
        let up = simd_float3(rotatedUp.x, rotatedUp.y, rotatedUp.z)
        
        let center = simd_float3(0, 0, 0)  // Always look at world center
        
        viewMatrix = simd_float4x4(lookAt: eye, center: center, up: up)
    }
    
    private func updateUniforms(for object: RenderObject) {
        guard let objectUniformBuffer = object.uniformBuffer else { return }
        
        // Calculate model matrix for this specific object
        let translationMatrix = simd_float4x4(translation: object.translation)
        let rotationMatrix = simd_float4x4(object.rotation)
        let modelMatrix = translationMatrix * rotationMatrix
        
        let inverseModelMatrix = modelMatrix.inverse
        let normalMatrix = simd_float3x3(
            simd_float3(inverseModelMatrix.columns.0.x, inverseModelMatrix.columns.0.y, inverseModelMatrix.columns.0.z),
            simd_float3(inverseModelMatrix.columns.1.x, inverseModelMatrix.columns.1.y, inverseModelMatrix.columns.1.z),
            simd_float3(inverseModelMatrix.columns.2.x, inverseModelMatrix.columns.2.y, inverseModelMatrix.columns.2.z)
        ).transpose
        
        let uniforms = Uniforms(
            modelMatrix: modelMatrix,
            viewMatrix: viewMatrix,
            projectionMatrix: projectionMatrix,
            normalMatrix: normalMatrix,
            lightDirection: normalize(simd_float3(0, 0, 1)),
            lightColor: simd_float3(1, 1, 1)
        )
        
        let uniformPointer = objectUniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1)
        uniformPointer.pointee = uniforms
    }
    
    func rotate(deltaX: Float, deltaY: Float) {
        rotateTrackball(deltaX: deltaX, deltaY: deltaY)
    }
    
    private func rotateTrackball(deltaX: Float, deltaY: Float) {
        let sensitivity: Float = 0.005
        
        // Convert screen delta to rotation angles
        let rotationX = deltaY * sensitivity   // Vertical drag rotates around X axis
        let rotationY = deltaX * sensitivity   // Horizontal drag rotates around Y axis
        
        // Get current rotation matrix and vectors
        let rotationMatrix = simd_float4x4(cameraRotation)
        let rightVector = simd_float3(rotationMatrix.columns.0.x, rotationMatrix.columns.0.y, rotationMatrix.columns.0.z)
        let upVector = simd_float3(rotationMatrix.columns.1.x, rotationMatrix.columns.1.y, rotationMatrix.columns.1.z)
        
        // Check if camera is upside down by comparing up vector with world up
        let worldUp = simd_float3(0, 1, 0)
        let upDot = dot(upVector, worldUp)
        
        // If camera is upside down (up dot < 0), invert Y rotation to maintain intuitive drag direction
        let adjustedRotationY = upDot < 0 ? -rotationY : rotationY
        
        // Create rotations
        let qy = simd_quatf(angle: adjustedRotationY, axis: simd_float3(0, 1, 0))
        let qx = simd_quatf(angle: rotationX, axis: rightVector)
        
        // Apply rotations: first Y (world space), then X (local space)
        cameraRotation = qy * qx * cameraRotation
        cameraRotation = simd_normalize(cameraRotation)
    }
    
    
    func zoom(delta: Float) {
        cameraRadius *= (1.0 - delta * 0.1)  // Negative because pinch in should zoom in
        cameraRadius = max(1.0, min(20.0, cameraRadius))
    }
    
    func translate(deltaX: Float, deltaY: Float) {
        // World translation could be implemented here if needed
        // For now, we focus on camera orbit rotation
    }
    
    func getObjectCount() -> Int {
        return renderObjects.count
    }
    
    func startRotation() {
        // No special setup needed for simple trackball rotation
    }
    
    func endRotation() {
        // No special cleanup needed for simple trackball rotation
    }
}

extension simd_float4x4 {
    init(rotationX angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, c, s, 0),
            simd_float4(0, -s, c, 0),
            simd_float4(0, 0, 0, 1)
        ))
    }
    
    init(rotationY angle: Float) {
        let c = cos(angle)
        let s = sin(angle)
        self.init(columns: (
            simd_float4(c, 0, -s, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(s, 0, c, 0),
            simd_float4(0, 0, 0, 1)
        ))
    }
    
    init(scale: Float) {
        self.init(columns: (
            simd_float4(scale, 0, 0, 0),
            simd_float4(0, scale, 0, 0),
            simd_float4(0, 0, scale, 0),
            simd_float4(0, 0, 0, 1)
        ))
    }
    
    init(translation: simd_float3) {
        self.init(columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(translation.x, translation.y, translation.z, 1)
        ))
    }
    
    init(perspectiveProjectionFov fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {
        let yScale = 1 / tan(fovy * 0.5)
        let xScale = yScale / aspectRatio
        let zRange = farZ - nearZ
        let zScale = farZ / zRange  // Left-handed: positive Z goes into screen
        let wzScale = -nearZ * farZ / zRange
        
        self.init(columns: (
            simd_float4(xScale, 0, 0, 0),
            simd_float4(0, yScale, 0, 0),
            simd_float4(0, 0, zScale, 1),  // Left-handed: +1 instead of -1
            simd_float4(0, 0, wzScale, 0)
        ))
    }
    
    init(lookAt eye: simd_float3, center: simd_float3, up: simd_float3) {
        // Left-handed: forward direction is toward target, not away from it
        let z = normalize(center - eye)  // Forward direction (positive Z)
        let x = normalize(cross(up, z))  // Right direction
        let y = cross(z, x)              // Up direction
        
        self.init(columns: (
            simd_float4(x.x, y.x, z.x, 0),
            simd_float4(x.y, y.y, z.y, 0),
            simd_float4(x.z, y.z, z.z, 0),
            simd_float4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
        ))
    }
    
    var inverse: simd_float4x4 {
        return simd_inverse(self)
    }
    
    var transpose: simd_float4x4 {
        return simd_transpose(self)
    }
}

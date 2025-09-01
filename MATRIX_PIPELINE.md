# Metal OBJ Viewer - Matrix Pipeline Documentation

## Overview
This document explains the matrix transformation pipeline used in the Metal OBJ Viewer application, detailing how Model, View, and Projection matrices are calculated and applied to render 3D objects.

## Coordinate System
The application uses a **left-handed coordinate system**:
- **X-axis**: Points to the right
- **Y-axis**: Points upward  
- **Z-axis**: Points into the screen (forward)

## Matrix Pipeline Flow

```
Object Space → [Model Matrix] → World Space → [View Matrix] → View Space → [Projection Matrix] → Clip Space
```

## 1. Model Matrix

The Model Matrix transforms vertices from object space to world space. Each `RenderObject` has its own transformation properties.

### Components
- **Translation**: Position of the object in world space
- **Rotation**: Orientation of the object (stored as quaternion)

### Calculation (MetalRenderer.swift:198-204)
```swift
private func updateUniforms(for object: RenderObject) {
    // Translation matrix moves object to its world position
    let translationMatrix = simd_float4x4(translation: object.translation)
    
    // Rotation matrix orients the object
    let rotationMatrix = simd_float4x4(object.rotation)
    
    // Combine: first rotate, then translate
    let modelMatrix = translationMatrix * rotationMatrix
}
```

### Translation Matrix Structure
```
[1  0  0  0]
[0  1  0  0]
[0  0  1  0]
[tx ty tz 1]
```

## 2. View Matrix

The View Matrix transforms vertices from world space to view space (camera space). It represents the camera's position and orientation in the world.

### Camera Orbit System
The camera orbits around the world origin (0,0,0) at a fixed radius, controlled by user input.

### Components
- **Camera Position (eye)**: Calculated from rotation and radius
- **Look-at Target (center)**: Always (0,0,0) - world origin
- **Up Vector**: Rotated with camera to maintain orientation

### Calculation (MetalRenderer.swift:181-200)
```swift
private func updateViewMatrix() {
    // Convert camera quaternion to rotation matrix
    let rotationMatrix = simd_float4x4(cameraRotation)
    
    // Initial camera position before rotation (looking down Z axis)
    let initialPosition = simd_float3(0, 0, cameraRadius)
    
    // Rotate camera position around origin
    let rotatedPosition = rotationMatrix * simd_float4(initialPosition, 1.0)
    let eye = simd_float3(rotatedPosition.x, rotatedPosition.y, rotatedPosition.z)
    
    // Rotate up vector to maintain proper orientation
    let initialUp = simd_float3(0, 1, 0)
    let rotatedUp = rotationMatrix * simd_float4(initialUp, 0.0)
    let up = simd_float3(rotatedUp.x, rotatedUp.y, rotatedUp.z)
    
    let center = simd_float3(0, 0, 0)  // Always look at world center
    
    // Create look-at matrix
    viewMatrix = simd_float4x4(lookAt: eye, center: center, up: up)
}
```

### Look-At Matrix Construction (MetalRenderer.swift:332-343)
```swift
init(lookAt eye: simd_float3, center: simd_float3, up: simd_float3) {
    // Left-handed: forward direction is toward target
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
```

## 3. Projection Matrix

The Projection Matrix transforms vertices from view space to clip space, applying perspective projection.

### Calculation (MetalRenderer.swift:131-136)
```swift
func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let aspect = Float(size.width) / Float(size.height)
    projectionMatrix = simd_float4x4(
        perspectiveProjectionFov: Float.pi / 4,  // 45 degrees FOV
        aspectRatio: aspect,
        nearZ: 0.1,
        farZ: 100.0
    )
}
```

### Perspective Projection Matrix (MetalRenderer.swift:317-330)
```swift
init(perspectiveProjectionFov fovy: Float, aspectRatio: Float, 
     nearZ: Float, farZ: Float) {
    let yScale = 1 / tan(fovy * 0.5)
    let xScale = yScale / aspectRatio
    let zRange = farZ - nearZ
    let zScale = farZ / zRange  // Left-handed: positive Z into screen
    let wzScale = -nearZ * farZ / zRange
    
    self.init(columns: (
        simd_float4(xScale, 0, 0, 0),
        simd_float4(0, yScale, 0, 0),
        simd_float4(0, 0, zScale, 1),  // Left-handed: +1 instead of -1
        simd_float4(0, 0, wzScale, 0)
    ))
}
```

## 4. Normal Matrix

The Normal Matrix is used to transform normal vectors correctly, maintaining their perpendicular relationship to surfaces after transformation.

### Calculation (MetalRenderer.swift:206-211)
```swift
// Normal matrix = transpose(inverse(modelMatrix))
let inverseModelMatrix = modelMatrix.inverse
let normalMatrix = simd_float3x3(
    simd_float3(inverseModelMatrix.columns.0.x, 
                inverseModelMatrix.columns.0.y, 
                inverseModelMatrix.columns.0.z),
    simd_float3(inverseModelMatrix.columns.1.x, 
                inverseModelMatrix.columns.1.y, 
                inverseModelMatrix.columns.1.z),
    simd_float3(inverseModelMatrix.columns.2.x, 
                inverseModelMatrix.columns.2.y, 
                inverseModelMatrix.columns.2.z)
).transpose
```

## 5. User Input and Camera Control

The camera system uses quaternion-based trackball rotation for intuitive 3D navigation. User drag input is converted to camera rotation around the world origin.

### Camera Control Features:
- **Orbit rotation**: Camera moves around world origin (0,0,0)
- **Quaternion-based**: Prevents gimbal lock and ensures smooth rotation
- **Touch/mouse input**: Drag gestures control camera orientation
- **Zoom support**: Adjusts camera distance from origin

For detailed trackball rotation implementation, see `TrackballRotation.md`.

## 6. Shader Integration

In the vertex shader (Shaders.metal), matrices are applied in sequence:

```metal
vertex VertexOut vertex_main(const VertexIn in [[stage_in]],
                             constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    // Transform position: Model → View → Projection
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = uniforms.viewMatrix * worldPosition;
    out.position = uniforms.projectionMatrix * viewPosition;
    
    // Transform normal for lighting
    out.worldNormal = uniforms.normalMatrix * in.normal;
    
    return out;
}
```

## 7. Multiple Object Support

Each object maintains its own:
- Vertex buffer for geometry
- Uniform buffer for transformation matrices
- Transform properties (position, rotation)

This architecture allows efficient rendering of multiple objects with different transformations in a single render pass.

## Matrix Multiplication Order

Matrix multiplication is **not commutative**. The order matters:
- `A * B ≠ B * A` in general
- Transformations are applied right-to-left: `Translation * Rotation * Vertex`
- This means: First rotate the vertex, then translate it

## Performance Considerations

1. **Uniform Buffer Updates**: Each object's uniforms are updated per frame only when needed
2. **Matrix Caching**: View and Projection matrices are shared across objects
3. **SIMD Optimization**: Using simd_float4x4 leverages hardware acceleration
4. **Quaternion Normalization**: Prevents numerical drift in rotations

## Debugging Tips

To debug transformation issues:
1. Check matrix multiplication order
2. Verify coordinate system consistency (left-handed throughout)
3. Ensure quaternions are normalized
4. Validate that normal matrix is correctly calculated
5. Use identity matrices to isolate transformation stages
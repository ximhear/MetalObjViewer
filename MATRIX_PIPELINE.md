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

### Trackball Rotation (MetalRenderer.swift:235-261)
The trackball rotation system allows intuitive 3D rotation using mouse/touch input:

```swift
private func rotateTrackball(deltaX: Float, deltaY: Float) {
    let sensitivity: Float = 0.005
    
    // Convert screen delta to rotation angles
    let rotationX = deltaY * sensitivity  // Vertical drag → X-axis rotation
    let rotationY = deltaX * sensitivity  // Horizontal drag → Y-axis rotation
    
    // Y rotation: always around world up vector
    let qy = simd_quatf(angle: rotationY, axis: simd_float3(0, 1, 0))
    
    // X rotation: around camera's right vector (first column of rotation matrix)
    let rotationMatrix = simd_float4x4(cameraRotation)
    let rightVector = simd_float3(rotationMatrix.columns.0.x, 
                                  rotationMatrix.columns.0.y, 
                                  rotationMatrix.columns.0.z)
    let qx = simd_quatf(angle: rotationX, axis: rightVector)
    
    // Apply rotations: Y (world space), then X (local space)
    cameraRotation = qy * qx * cameraRotation
    cameraRotation = simd_normalize(cameraRotation)
}
```

### Key Features:
- **Horizontal drag**: Rotates around world Y-axis (yaw)
- **Vertical drag**: Rotates around camera's local X-axis (pitch)
- **No gimbal lock**: Using quaternions prevents rotation singularities
- **Smooth interpolation**: Quaternions provide smooth rotation paths

### Detailed Explanation of Trackball Rotation

#### Core Concept
Trackball rotation simulates rotating a transparent sphere with your hand, providing intuitive 3D camera control.

#### Two Rotation Axes
1. **Horizontal Drag (deltaX)**: Rotates around world Y-axis (Yaw)
2. **Vertical Drag (deltaY)**: Rotates around camera's local X-axis/Right vector (Pitch)

#### Why Different Axes?

**Y-axis Rotation (Horizontal Drag)**
```swift
let qy = simd_quatf(angle: rotationY, axis: simd_float3(0, 1, 0))
```
- Always uses world Y-axis (0, 1, 0)
- Reason: Horizontal dragging should maintain "up" direction while looking left/right
- Natural behavior like a standing person looking around

**X-axis Rotation (Vertical Drag)**
```swift
let rotationMatrix = simd_float4x4(cameraRotation)
let rightVector = simd_float3(rotationMatrix.columns.0.x, 
                              rotationMatrix.columns.0.y, 
                              rotationMatrix.columns.0.z)
let qx = simd_quatf(angle: rotationX, axis: rightVector)
```
- Uses camera's current Right vector
- Reason: Up/down dragging should always rotate relative to screen orientation

#### Understanding Right and Up Vectors

**Right Vector (Right Direction)**
```
Rotation Matrix Columns:
[Rx]   [Ux]   [Fx]   [Tx]
[Ry]   [Uy]   [Fy]   [Ty]
[Rz]   [Uz]   [Fz]   [Tz]
[0 ]   [0 ]   [0 ]   [1 ]
 ↑      ↑      ↑      ↑
Right   Up   Forward Translation
```

Why first column is Right vector:
- Rotation matrix represents transformation of basis vectors
- Column 1: X-axis basis (1,0,0) transformed = Right direction
- Column 2: Y-axis basis (0,1,0) transformed = Up direction  
- Column 3: Z-axis basis (0,0,1) transformed = Forward direction

**Up Vector (Up Direction)**
In View Matrix calculation, Up vector is also rotated:
```swift
let initialUp = simd_float3(0, 1, 0)
let rotatedUp = rotationMatrix * simd_float4(initialUp, 0.0)
```
- Maintains correct orientation when camera tilts

#### Importance of Rotation Order

```swift
cameraRotation = qy * qx * cameraRotation
```

Order matters because:
1. **qy (Y-axis rotation)**: Applied first in world space
2. **qx (X-axis rotation)**: Applied in local space
3. **cameraRotation**: Accumulated with existing rotation

Why this order:
- Y rotation first ensures consistent horizontal rotation
- X rotation after applies up/down relative to current view
- Reverse order would cause unintuitive mixed rotations

#### Solving Gimbal Lock

**Problem**: 
- Euler angles can cause axes to align at certain angles
- Example: After 90° X rotation, Y and Z axes produce same effect

**Solution**:
1. **Quaternions**: 4D representation prevents gimbal lock
2. **Dynamic Axis Calculation**: Right vector computed from current rotation
3. **Normalization**: `simd_normalize(cameraRotation)` prevents numerical drift

#### Practical Examples

**Scenario 1: Looking Forward**
- Right vector = (1, 0, 0) - pure X-axis
- Drag up → Rotate around X-axis → Look up/down

**Scenario 2: Looking 90° Left**  
- Right vector ≈ (0, 0, -1) - Z-axis direction
- Drag up → Rotate around transformed Right vector → Still screen-relative up/down

**Scenario 3: Looking Up**
- Right vector remains horizontal
- Stable rotation continues (no gimbal lock)

#### Sensitivity Control
```swift
let sensitivity: Float = 0.005
```
- Converts pixel movement to radian angles
- Lower value = more precise control
- Higher value = faster rotation

#### Summary
The trackball rotation system's key principles:
1. **Horizontal rotation**: Always uses world Y-axis (consistent left/right)
2. **Vertical rotation**: Uses camera's Right vector (screen-relative up/down)
3. **Quaternions**: Prevent gimbal lock and ensure smooth rotation
4. **Dynamic axis calculation**: Rotation axes match current camera orientation

This provides intuitive and predictable camera control regardless of viewing direction.

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
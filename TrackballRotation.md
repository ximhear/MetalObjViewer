# Trackball Rotation과 Model/View Matrix 설정

## 개요
MetalObjViewer에서 구현된 trackball rotation 시스템은 사용자의 드래그 입력을 3D 공간에서의 카메라 회전으로 변환하여 직관적인 3D 객체 조작을 제공합니다.

## 좌표계 및 기본 설정

### 좌표계
- **Left-handed coordinate system** 사용
- **Z축**: 화면 안쪽으로 향함 (positive Z)
- **Y축**: 위쪽 (positive Y)
- **X축**: 오른쪽 (positive X)

### 카메라 설정
```swift
// 카메라 기본 설정
private var cameraRadius: Float = 5.0  // 카메라와 원점 간의 거리
private var cameraRotation = simd_quatf(real: 1, imag: SIMD3<Float>(0, 0, 0))  // 쿼터니언으로 회전 관리
```

## Trackball Rotation 구현

### 1. 드래그 입력 처리
```swift
func rotate(deltaX: Float, deltaY: Float) {
    rotateTrackball(deltaX: deltaX, deltaY: deltaY)
}
```

### 2. 회전 계산 및 적용
```swift
private func rotateTrackball(deltaX: Float, deltaY: Float) {
    let sensitivity: Float = 0.005
    
    // 화면 드래그를 회전 각도로 변환
    let rotationX = deltaY * sensitivity   // 세로 드래그 → X축 회전
    let rotationY = deltaX * sensitivity   // 가로 드래그 → Y축 회전
    
    // 현재 카메라의 방향 벡터들 계산
    let rotationMatrix = simd_float4x4(cameraRotation)
    let rightVector = simd_float3(rotationMatrix.columns.0.x, rotationMatrix.columns.0.y, rotationMatrix.columns.0.z)
    let upVector = simd_float3(rotationMatrix.columns.1.x, rotationMatrix.columns.1.y, rotationMatrix.columns.1.z)
    
    // 카메라가 뒤집혔는지 확인 (중요한 수정사항!)
    let worldUp = simd_float3(0, 1, 0)
    let upDot = dot(upVector, worldUp)
    
    // 카메라가 뒤집혔을 때 Y축 회전 방향 보정
    let adjustedRotationY = upDot < 0 ? -rotationY : rotationY
    
    // 쿼터니언 생성
    let qy = simd_quatf(angle: adjustedRotationY, axis: simd_float3(0, 1, 0))  // World Y축 기준
    let qx = simd_quatf(angle: rotationX, axis: rightVector)  // 카메라 Right 벡터 기준
    
    // 회전 적용: Y축 회전 → X축 회전 → 기존 회전
    cameraRotation = qy * qx * cameraRotation
    cameraRotation = simd_normalize(cameraRotation)
}
```

## View Matrix 생성

### 1. 카메라 위치 계산
```swift
private func updateViewMatrix() {
    // 쿼터니언을 4x4 행렬로 변환
    let rotationMatrix = simd_float4x4(cameraRotation)
    
    // 초기 카메라 위치 (Z축 방향)
    let initialPosition = simd_float3(0, 0, cameraRadius)
    
    // 회전 적용하여 실제 카메라 위치 계산
    let rotatedPosition = rotationMatrix * simd_float4(initialPosition, 1.0)
    let eye = simd_float3(rotatedPosition.x, rotatedPosition.y, rotatedPosition.z)
    
    // Up 벡터도 함께 회전
    let initialUp = simd_float3(0, 1, 0)
    let rotatedUp = rotationMatrix * simd_float4(initialUp, 0.0)
    let up = simd_float3(rotatedUp.x, rotatedUp.y, rotatedUp.z)
    
    // 항상 원점을 바라보도록 설정
    let center = simd_float3(0, 0, 0)
    
    // View Matrix 생성 (Look-At)
    viewMatrix = simd_float4x4(lookAt: eye, center: center, up: up)
}
```

### 2. Look-At 행렬 구현
```swift
init(lookAt eye: simd_float3, center: simd_float3, up: simd_float3) {
    // Left-handed: forward 방향은 target 쪽
    let z = normalize(center - eye)  // Forward 방향 (positive Z)
    let x = normalize(cross(up, z))  // Right 방향
    let y = cross(z, x)              // Up 방향
    
    self.init(columns: (
        simd_float4(x.x, y.x, z.x, 0),
        simd_float4(x.y, y.y, z.y, 0),
        simd_float4(x.z, y.z, z.z, 0),
        simd_float4(-dot(x, eye), -dot(y, eye), -dot(z, eye), 1)
    ))
}
```

## Model Matrix 처리

### 개별 객체별 Model Matrix
```swift
private func updateUniforms(for object: RenderObject) {
    // 객체별 변환 행렬
    let translationMatrix = simd_float4x4(translation: object.translation)
    let rotationMatrix = simd_float4x4(object.rotation)
    let modelMatrix = translationMatrix * rotationMatrix
    
    // Normal Matrix 계산 (조명 계산용)
    let inverseModelMatrix = modelMatrix.inverse
    let normalMatrix = simd_float3x3(
        simd_float3(inverseModelMatrix.columns.0.x, inverseModelMatrix.columns.0.y, inverseModelMatrix.columns.0.z),
        simd_float3(inverseModelMatrix.columns.1.x, inverseModelMatrix.columns.1.y, inverseModelMatrix.columns.1.z),
        simd_float3(inverseModelMatrix.columns.2.x, inverseModelMatrix.columns.2.y, inverseModelMatrix.columns.2.z)
    ).transpose
    
    // Uniform 구조체에 데이터 설정
    let uniforms = Uniforms(
        modelMatrix: modelMatrix,
        viewMatrix: viewMatrix,
        projectionMatrix: projectionMatrix,
        normalMatrix: normalMatrix,
        lightDirection: normalize(simd_float3(0, 0, 1)),
        lightColor: simd_float3(1, 1, 1)
    )
}
```

## 중요한 수정사항

### 카메라 뒤집힘 문제 해결
기존 문제점:
- X축으로 180도 회전 후 Y축 드래그 시 반대 방향으로 회전
- 직관적이지 않은 조작감

해결 방법:
```swift
// 카메라의 up 벡터와 world up 벡터 비교
let worldUp = simd_float3(0, 1, 0)
let upDot = dot(upVector, worldUp)

// 카메라가 뒤집혔을 때 Y축 회전 방향 보정
let adjustedRotationY = upDot < 0 ? -rotationY : rotationY
```

이 수정으로 인해:
- 카메라가 어떤 각도에 있든 드래그 방향이 일관됨
- 사용자에게 직관적인 3D 조작 경험 제공

## Projection Matrix

### Perspective Projection (Left-handed)
```swift
init(perspectiveProjectionFov fovy: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {
    let yScale = 1 / tan(fovy * 0.5)
    let xScale = yScale / aspectRatio
    let zRange = farZ - nearZ
    let zScale = farZ / zRange  // Left-handed: positive Z
    let wzScale = -nearZ * farZ / zRange
    
    self.init(columns: (
        simd_float4(xScale, 0, 0, 0),
        simd_float4(0, yScale, 0, 0),
        simd_float4(0, 0, zScale, 1),  // Left-handed: +1
        simd_float4(0, 0, wzScale, 0)
    ))
}
```

## 렌더링 파이프라인에서의 적용

```swift
func draw(in view: MTKView) {
    // View Matrix 업데이트
    updateViewMatrix()
    
    // 각 객체별로 렌더링
    for object in renderObjects {
        // 객체별 Uniform 업데이트
        updateUniforms(for: object)
        
        // 버퍼 설정 및 드로우 콜
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(objectUniformBuffer, offset: 0, index: 1)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: object.vertices.count)
    }
}
```

## 정리

1. **쿼터니언 기반 회전**: 부드럽고 안정적인 3D 회전
2. **카메라 궤도 운동**: 항상 원점을 중심으로 회전
3. **방향 보정**: 카메라 뒤집힘 상황에서도 직관적인 조작
4. **개별 객체 관리**: 각 객체마다 독립적인 Model Matrix
5. **Left-handed 좌표계**: Metal 렌더링에 최적화된 좌표계 사용

이 구현을 통해 사용자는 자연스럽고 직관적인 3D 객체 조작 경험을 얻을 수 있습니다.
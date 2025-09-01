# Trackball Rotation 수학적 분석

## 개요
이 문서는 MetalObjViewer의 `rotateTrackball` 함수에서 카메라 회전을 계산하는 수학적 과정을 상세히 분석합니다.

## 함수 구조
```swift
private func rotateTrackball(deltaX: Float, deltaY: Float) {
    let sensitivity: Float = 0.005
    
    // 1. 화면 드래그를 회전 각도로 변환
    let rotationX = -deltaY * sensitivity   // 세로 드래그 → X축 회전 (음수로 반전)
    let rotationY = deltaX * sensitivity    // 가로 드래그 → Y축 회전
    
    // 2. 현재 카메라 회전에서 방향 벡터 추출
    let rotationMatrix = simd_float4x4(cameraRotation)
    let rightVector = simd_float3(rotationMatrix.columns.0.x, rotationMatrix.columns.0.y, rotationMatrix.columns.0.z)
    let upVector = simd_float3(rotationMatrix.columns.1.x, rotationMatrix.columns.1.y, rotationMatrix.columns.1.z)
    
    // 3. 카메라 뒤집힘 감지 및 보정
    let worldUp = simd_float3(0, 1, 0)
    let upDot = dot(upVector, worldUp)
    let adjustedRotationY = upDot < 0 ? -rotationY : rotationY
    
    // 4. 쿼터니언 회전 생성
    let qy = simd_quatf(angle: adjustedRotationY, axis: simd_float3(0, 1, 0))
    let qx = simd_quatf(angle: rotationX, axis: rightVector)
    
    // 5. 회전 적용 및 정규화
    cameraRotation = qy * qx * cameraRotation
    cameraRotation = simd_normalize(cameraRotation)
}
```

## 1. 입력 변환 (Input Transformation)

### 화면 좌표계에서 회전 각도로 변환
```
deltaX → rotationY = deltaX * sensitivity
deltaY → rotationX = -deltaY * sensitivity (음수로 반전)
```

**수학적 의미:**
- `deltaX`: 화면에서 좌우 드래그 픽셀 거리
- `deltaY`: 화면에서 상하 드래그 픽셀 거리  
- `sensitivity = 0.005`: 픽셀당 라디안 변환 계수

**음수 반전 이유:**
- 화면 좌표계: Y축이 아래쪽으로 증가
- 3D 좌표계: Y축이 위쪽으로 증가
- 위로 드래그(`-deltaY`) → 카메라가 위를 보도록 회전(`+rotationX`)

## 2. 회전 행렬에서 방향 벡터 추출

### 현재 카메라 회전 행렬
```
R = [Rx  Ux  Fx  0]
    [Ry  Uy  Fy  0]  
    [Rz  Uz  Fz  0]
    [0   0   0   1]
```

여기서:
- **Right Vector** `R⃗ = (Rx, Ry, Rz)`: 카메라 기준 오른쪽 방향
- **Up Vector** `U⃗ = (Ux, Uy, Uz)`: 카메라 기준 위쪽 방향  
- **Forward Vector** `F⃗ = (Fx, Fy, Fz)`: 카메라 기준 전방 방향

### 수학적 배경
회전 행렬의 각 열은 표준 기저 벡터를 변환한 결과입니다:

```
R * [1, 0, 0, 0]ᵀ = [Rx, Ry, Rz, 0]ᵀ  (Right Vector)
R * [0, 1, 0, 0]ᵀ = [Ux, Uy, Uz, 0]ᵀ  (Up Vector)
R * [0, 0, 1, 0]ᵀ = [Fx, Fy, Fz, 0]ᵀ  (Forward Vector)
```

## 3. 카메라 뒤집힘 감지

### 내적을 통한 방향 판별
```swift
upDot = dot(upVector, worldUp) = Ux*0 + Uy*1 + Uz*0 = Uy
```

**수학적 분석:**
- `upDot > 0`: 카메라 Up 벡터가 월드 Up 방향과 동일한 쪽
- `upDot < 0`: 카메라가 뒒집힌 상태 (Up 벡터가 아래쪽)
- `upDot = 0`: 카메라가 수평 (임계점)

### Y축 회전 보정
```
adjustedRotationY = {
    rotationY     if upDot >= 0
    -rotationY    if upDot < 0
}
```

**물리적 의미:**
카메라가 뒤집혔을 때 가로 드래그 방향을 반전시켜 직관적인 조작감을 유지합니다.

## 4. 쿼터니언 회전 생성

### Y축 회전 쿼터니언 (Yaw)
```
qy = cos(θy/2) + sin(θy/2) * (0, 1, 0)
   = cos(adjustedRotationY/2) + sin(adjustedRotationY/2) * j
```

여기서 `θy = adjustedRotationY`이고, `j`는 Y축 단위 벡터입니다.

### X축 회전 쿼터니언 (Pitch)  
```
qx = cos(θx/2) + sin(θx/2) * rightVector
   = cos(rotationX/2) + sin(rotationX/2) * (Rx, Ry, Rz)
```

여기서 `θx = rotationX`입니다.

## 5. 회전 조합 (Quaternion Composition)

### 회전 순서
```
cameraRotation_new = qy * qx * cameraRotation_old
```

**수학적 해석:**
1. `cameraRotation_old`: 기존 카메라 회전
2. `qx`: 카메라의 로컬 X축(Right Vector) 기준 회전 적용
3. `qy`: 월드 Y축 기준 회전 적용

### 쿼터니언 곱셈 순서의 중요성

쿼터니언에서 `A * B`는 "B를 먼저 적용하고, A를 나중에 적용"을 의미합니다.

따라서 `qy * qx * cameraRotation`는:
1. `cameraRotation`: 기존 회전 상태
2. `qx`: 카메라 로컬 X축 기준 pitch 회전
3. `qy`: 월드 Y축 기준 yaw 회전

### 물리적 의미
- **Pitch 먼저**: 카메라의 현재 방향을 기준으로 위/아래 회전
- **Yaw 나중에**: 월드 기준으로 좌/우 회전

이 순서로 인해 자연스러운 trackball 동작이 구현됩니다.

## 6. 쿼터니언 정규화

### 수학적 필요성
```
||q|| = √(w² + x² + y² + z²) = 1
```

부동소수점 연산의 누적 오차로 인해 쿼터니언의 크기가 1에서 벗어날 수 있습니다.

### 정규화 공식
```
q_normalized = q / ||q||
```

정규화되지 않은 쿼터니언은 회전과 함께 스케일링을 일으키므로 반드시 정규화해야 합니다.

## 수학적 특성 분석

### 1. 연속성 (Continuity)
- 쿼터니언 보간은 구면에서 이루어지므로 부드러운 회전 경로를 보장
- 작은 `deltaX`, `deltaY` 입력에 대해 연속적인 회전 변화

### 2. 가역성 (Reversibility)  
- `rotateTrackball(-deltaX, -deltaY)`를 호출하면 이전 상태로 복원
- 쿼터니언의 역원: `q⁻¹ = (w, -x, -y, -z) / ||q||²`

### 3. 짐벌 락 방지 (Gimbal Lock Avoidance)
- 오일러 각 대신 쿼터니언 사용으로 특이점 회피
- 모든 방향에서 일관된 회전 축 제공

### 4. 수치적 안정성 (Numerical Stability)
- `simd_normalize`를 통한 정기적 정규화
- 부동소수점 오차 누적 방지

## 좌표계 변환

### 월드 좌표계 → 카메라 좌표계
```
P_camera = R⁻¹ * (P_world - T_camera)
```

여기서:
- `R`: 카메라 회전 행렬
- `T_camera`: 카메라 위치 (원점에서 `cameraRadius` 거리)

### 카메라 위치 계산
```swift
let initialPosition = simd_float3(0, 0, -cameraRadius)
let rotatedPosition = rotationMatrix * simd_float4(initialPosition, 1.0)
let eye = simd_float3(rotatedPosition.x, rotatedPosition.y, rotatedPosition.z)
```

**수학적 표현:**
```
eye = R * (0, 0, -r)ᵀ
```

여기서 `r = cameraRadius`입니다.

## 성능 고려사항

### 1. 사전 계산 최적화
- `rotationMatrix` 한 번만 계산 후 재사용
- 벡터 추출을 위한 중복 계산 최소화

### 2. SIMD 활용
- `simd_float3`, `simd_float4x4` 하드웨어 가속 활용
- 벡터 연산의 병렬 처리

### 3. 삼각함수 최적화
- 작은 각도에서 `sin(θ/2) ≈ θ/2`, `cos(θ/2) ≈ 1` 근사 가능
- 하지만 정확성을 위해 정확한 계산 사용

## 결론

trackball rotation 시스템은 다음 수학적 원리들을 조합하여 구현됩니다:

1. **선형 변환**: 화면 좌표 → 회전 각도
2. **행렬 분해**: 회전 행렬에서 방향 벡터 추출  
3. **내적**: 카메라 방향 판별
4. **쿼터니언 대수**: 3D 회전 표현 및 조합
5. **정규화**: 수치적 안정성 보장

이러한 수학적 기반을 통해 직관적이고 안정적인 3D 카메라 제어가 가능합니다.
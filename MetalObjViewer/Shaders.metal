#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoord;
};

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float3x3 normalMatrix;
    float3 lightDirection;
    float3 lightColor;
};

vertex VertexOut vertex_main(Vertex in [[stage_in]],
                           constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOut out;
    
    float4 worldPosition = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPosition.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPosition;
    out.worldNormal = uniforms.normalMatrix * in.normal;
    out.texCoord = in.texCoord;
    
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                            constant Uniforms& uniforms [[buffer(0)]]) {
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(-uniforms.lightDirection);
    
    float ambient = 0.2;
    float diffuse = max(dot(normal, lightDir), 0.0);
    
    float3 lighting = uniforms.lightColor * (ambient + diffuse);
    float3 baseColor = float3(0.7, 0.7, 0.9);
    
    return float4(baseColor * lighting, 1.0);
}
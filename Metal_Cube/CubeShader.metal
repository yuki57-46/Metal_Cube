//
//  CubeShader.metal
//  Metal_Cube
//
//  Created by yuki on 2025/11/16.
//

#include <metal_stdlib>
using namespace metal;


struct VertexIn {
    float3 pos [[attribute(0)]];
    float3 color [[attribute(1)]];
};

struct VertexOut {
    float4 pos [[position]];
    float3 color;
};

vertex VertexOut vs_cube(VertexIn in [[stage_in]], constant float4x4 &mvp [[buffer(1)]])
{
    VertexOut out;
    out.pos = mvp * float4(in.pos, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 fs_cube(VertexOut in [[stage_in]])
{
    return float4(in.color, 1.0);
}

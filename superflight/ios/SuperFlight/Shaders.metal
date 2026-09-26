// Shaders.metal — vertex/fragment per il gioco di volo.

#include <metal_stdlib>
using namespace metal;

struct FlyUniforms {
    float4x4 viewProj;
    float3 cameraPos;
    float time;
    float3 pad;
};

struct InstanceData {
    float4x4 model;
    float4 color;
};

struct VertexOut {
    float4 pos [[position]];
    float3 world;
    float3 normal;
    float4 color;
    float3 local;
};

// Cubo unitario centrato: 36 vertici (posizione, normale)
constant float3 cubeVerts[36] = {
    float3(-1,-1,-1), float3(1,-1,-1), float3(1,1,-1),
    float3(-1,-1,-1), float3(1,1,-1),  float3(-1,1,-1),
    float3(1,-1,1),  float3(-1,-1,1), float3(-1,1,1),
    float3(1,-1,1),  float3(-1,1,1),  float3(1,1,1),
    float3(-1,-1,1), float3(-1,-1,-1), float3(-1,1,-1),
    float3(-1,-1,1), float3(-1,1,-1), float3(-1,1,1),
    float3(1,-1,1),  float3(1,-1,-1), float3(1,1,-1),
    float3(1,-1,1),  float3(1,1,-1),  float3(1,1,1),
    float3(-1,1,1),  float3(-1,1,-1), float3(1,1,-1),
    float3(-1,1,1),  float3(1,1,-1),  float3(1,1,1),
    float3(-1,-1,-1), float3(-1,-1,1), float3(1,-1,1),
    float3(-1,-1,-1), float3(1,-1,1),  float3(1,-1,-1),
};
constant float3 cubeNormals[6] = {
    float3(0,0,-1), float3(0,0,1), float3(-1,0,0),
    float3(1,0,0), float3(0,1,0), float3(0,-1,0)
};

// Il layout reale dei vertici nel buffer C: pos(3) + normal(3) interleaved.
// Qui usiamo il vertice index-based: leggiamo solo vertex_id.
vertex VertexOut vertexMain(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            constant FlyUniforms &u [[buffer(1)]],
                            const device InstanceData* instances [[buffer(2)]],
                            constant int32_t &count [[buffer(3)]])
{
    VertexOut out;
    uint vi = vid % 36;
    uint face = vi / 6;
    float3 lp = cubeVerts[vi];
    float3 n = cubeNormals[face];

    float4 world = instances[iid].model * float4(lp, 1.0);
    out.pos = u.viewProj * world;
    out.world = world.xyz;
    float3 wn = normalize((instances[iid].model * float4(n, 0.0)).xyz);
    out.normal = wn;
    out.color = instances[iid].color;
    out.local = lp;
    return out;
}

// Finestre procedurali: griglia emissiva sulle facciate, scuro sul tetto.
fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]])
{
    float3 n = normalize(in.normal);
    float roof = step(0.7, n.y);                      // tetti = scuri

    // Coordinate locali per la griglia finestre
    float2 uv;
    if (abs(n.y) > 0.5) uv = in.local.xz;
    else if (abs(n.x) > 0.5) uv = in.local.zy;
    else uv = in.local.xy;

    float2 grid = floor(uv * float2(3.0, 6.0));
    float cell = fract(sin(dot(grid, float2(12.9898, 78.233))) * 43758.5453);
    float lit = step(0.55, cell) * (1.0 - roof);

    // Luce direzionale + ambiento
    float diff = max(0.0, dot(n, normalize(float3(0.4, 0.8, 0.3))));
    float3 base = in.color.rgb * (0.25 + 0.75 * diff);
    float3 winGlow = in.color.rgb * 2.2 * lit;
    float3 col = base + winGlow;

    // Nebbia atmosferica in lontananza
    float dist = length(u.cameraPos - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    float3 fogCol = float3(0.55, 0.65, 0.85);
    col = mix(col, fogCol, clamp(fog, 0.0, 0.85));
    return float4(col, 1.0);
}

// Glow additivo per anelli/boost/particelle.
fragment float4 glowFragment(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]])
{
    // bordo più luminoso: basato sulla coordinata locale
    float edge = 1.0 - abs(in.local.y);
    float a = in.color.a * (0.35 + 0.65 * edge);
    float3 col = in.color.rgb * (1.5 + edge);
    float dist = length(u.cameraPos - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    col = mix(col, float3(0.55, 0.65, 0.85), clamp(fog, 0.0, 0.85));
    return float4(col * a, a);
}

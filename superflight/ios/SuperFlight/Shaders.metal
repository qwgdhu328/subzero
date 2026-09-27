// Shaders.metal — rendering 4K/HDR: cubi istanziati (città/terra/nuvole), mesh
// personaggi (sfere/capsule), mantello animato, tessuti, glow (anelli/laser/
// particelle), cielo procedurale con sole e stelle, post-process bloom+tonemap.

#include <metal_stdlib>
using namespace metal;

// Layout identico su Swift e Metal: solo float4x4 e float4 (niente float3,
// il cui allineamento 16 in Metal diverge dallo stride 16 di SIMD3 in Swift).
struct FlyUniforms {
    float4x4 viewProj;        // 0
    float4x4 invViewProj;     // 64
    float4   cameraPosTime;   // 128: xyz = posizione camera, w = tempo
    float4   fwdAspect;       // 144: xyz = direzione vista, w = aspect
    float4   sunPre;          // 160: xyz = direzione sole, w = scala prepass
    float4   bufferSizePad;   // 176: xy = dimensioni buffer
};

// Uniform delle ombre (W1 del piano AAA): matrice sole, bias e risoluzione
// della shadow map. Solo float4x4/float4 (allineamento identico a Swift).
struct ShadowUniforms {
    float4x4 sunViewProj;      // 0: view-proj ortografica dal sole
    float4   sunPosRadius;     // 64: xyz = posizione sole, w = raggio area
    float4   biasResolution;   // 80: x = bias depth, y = risoluzione shadow map
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
    float3 scale;   // dimensione mondo del box (cubi)
    float2 uv;      // coordinate tessuto (mantello) / ndc (cielo)
};

// Output dei vertex/fragment full-screen (cielo, post-process).
struct PostOut {
    float4 pos [[position]];
    float2 uv;
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
    float3(-1,1,1),  float3(1,1,-1), float3(1,1,1),
    float3(-1,-1,-1), float3(-1,-1,1), float3(1,-1,1),
    float3(-1,-1,-1), float3(1,-1,1),  float3(1,-1,-1),
};
constant float3 cubeNormals[6] = {
    float3(0,0,-1), float3(0,0,1), float3(-1,0,0),
    float3(1,0,0), float3(0,1,0), float3(0,-1,0)
};

static inline float3 boxScale(float4x4 m) {
    return float3(length(m.columns[0].xyz),
                  length(m.columns[1].xyz),
                  length(m.columns[2].xyz));
}

// Hash senza artefatti di banda.
static inline float hash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
static inline float hash13(float3 p) {
    float3 p3 = fract(p * 0.1031);
    p3 += dot(p3, float3(p3.z, p3.y, p3.x) + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}
// Value noise 2D per variazioni morbide (asfalto, nuvole).
static inline float valueNoise2(float2 p) {
    float2 i = floor(p), f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1, 0));
    float c = hash12(i + float2(0, 1));
    float d = hash12(i + float2(1, 1));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ------------------------------------------------------------ //
//  Shadow mapping (W1 del piano AAA): campionamento PCF 3×3 della shadow
//  map renderizzata dal punto di vista del sole.

// Ritorna 1 = pieno sole, 0 = in ombra (PCF 3×3, bordi morbidi).
float shadowFactor(float3 worldPos, float3 n, texture2d<float> shadowMap,
                   sampler shadowSamp, constant ShadowUniforms &shadowU) {
    float4 sc = shadowU.sunViewProj * float4(worldPos, 1.0);
    float3 coord = sc.xyz / sc.w;
    coord.y = -coord.y;                    // flip Y: la texture ha origine in alto
    coord.xy = coord.xy * 0.5 + 0.5;       // NDC → [0,1]
    coord.z -= shadowU.biasResolution.x;
    // Fuori dal frustum del sole: nessuna occlusione (bordi dell'area coperta).
    if (any(coord.xy < 0.0) || any(coord.xy > 1.0) || coord.z > 1.0) { return 1.0; }
    // Ricevitore che non guarda il sole: in ombra per contatto (controluce).
    if (dot(n, normalize(shadowU.sunPosRadius.xyz - worldPos)) <= 0.0) { return 0.0; }

    float texel = 1.0 / shadowU.biasResolution.y;
    float sum = 0.0;
    for (int y = -1; y <= 1; ++y) {
        for (int x = -1; x <= 1; ++x) {
            float2 uv = coord.xy + float2(float(x), float(y)) * texel;
            float d = shadowMap.sample(shadowSamp, uv).r;
            sum += (d < coord.z) ? 0.0 : 1.0;
        }
    }
    return sum / 9.0;
}

// ------------------------------------------------------------ //
//  PBR Cook-Torrance (W2 del piano AAA): BRDF GGX per edifici e mantello.

constant float kPi = 3.14159265358979323846;

// Fresnel-Schlick: il riflesso cresce a incidencee radente.
inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Distribuzione GGX (Trowbridge-Reitz): modello a microfacets.
inline float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    denom = kPi * denom * denom;
    return a2 / max(denom, 0.0001);
}

// Geometry Smith-Schlick: mascheratura/ombreggiatura dei microfacets.
inline float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

inline float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotL, roughness) * geometrySchlickGGX(NdotV, roughness);
}

// BRDF completa Cook-Torrance: diffuso Lambert + speculare GGX.
inline float3 cookTorranceBRDF(float3 N, float3 V, float3 L,
                               float roughness, float metallic, float3 baseColor) {
    float3 H = normalize(V + L);
    float NdotV = max(dot(N, V), 0.001);
    float NdotL = max(dot(N, L), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float HdotV = max(dot(H, V), 0.0);

    float3 F0 = mix(float3(0.04), baseColor, metallic);   // 0.04 dielettrico, albedo metallo
    float3 F = fresnelSchlick(HdotV, F0);
    float D = distributionGGX(NdotH, roughness);
    float G = geometrySmith(NdotV, NdotL, roughness);

    float3 specular = (D * F * G) / (4.0 * NdotV * NdotL + 0.001);
    float3 kD = (float3(1.0) - F) * (1.0 - metallic);     // i metalli non hanno diffuso
    return kD * baseColor / kPi + specular;
}

// Roughness/metallicità procedurali (da PBR_Shaders.metal del piano):
// il vetro è lucido, il cemento ruvido, le griglie dei tetti metalliche.
inline void cityMaterial(float3 color, float3 worldPos, float3 n,
                         thread float &roughness, thread float &metallic) {
    float gridX = step(0.82, abs(sin(worldPos.x * 0.3)));
    float gridZ = step(0.82, abs(sin(worldPos.z * 0.3)));
    metallic = mix(0.0, 0.8, gridX * gridZ * step(0.5, abs(n.y)));
    float lum = dot(color, float3(0.299, 0.587, 0.114));
    roughness = lum < 0.3 ? 0.12 : 0.72;                  // finestre lucide / cemento
    roughness = clamp(roughness + 0.08 * sin(worldPos.x * 0.1) * cos(worldPos.y * 0.1), 0.08, 1.0);
}

// ------------------------------------------------------------ //
//  Cielo procedurale: gradiente, sole con alone, stelle in quota

float3 skyColor(float3 dir, float3 sunDir, float altT, float time) {
    float dusk = 1.0 - smoothstep(0.05, 0.45, sunDir.y);
    float horiz = pow(1.0 - saturate(dir.y), 2.2);

    float3 zenith  = mix(float3(0.20, 0.40, 0.86), float3(0.15, 0.24, 0.55), dusk);
    float3 horizon = mix(float3(0.74, 0.86, 0.98), float3(0.99, 0.58, 0.36), dusk);
    float3 col = mix(zenith, horizon, horiz);

    // Sole: disco + alone largo (HDR: valori > 1, il bloom li fa brillare).
    float sd = max(0.0, dot(dir, sunDir));
    float vis = smoothstep(-0.08, 0.05, sunDir.y);
    col += float3(1.0, 0.88, 0.65) * pow(sd, 1100.0) * 14.0 * vis;
    col += float3(1.0, 0.72, 0.42) * pow(sd, 7.0) * 0.22 * vis;
    col += float3(1.0, 0.55, 0.30) * pow(sd, 1.5) * 0.05 * dusk;

    // Stelle: appaiono sopra i 1500 m, più fitte e stabili verso lo spazio.
    float3 cell = floor(dir * 240.0);
    float star = step(0.9975, hash13(cell));
    float tw = 0.55 + 0.45 * sin(time * 3.0 + hash13(cell + 7.7) * 40.0);
    float starVis = smoothstep(0.12, 0.45, dir.y) * (0.55 + 0.45 * altT);
    col += float3(0.85, 0.92, 1.0) * star * tw * starVis * (1.0 - vis * 0.6);

    return col;
}

// ------------------------------------------------------------ //
//  Vertex: cubi istanziati (città, terra, nuvole)

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
    out.normal = normalize((instances[iid].model * float4(n, 0.0)).xyz);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = boxScale(instances[iid].model);
    out.uv = float2(0.0);
    return out;
}

// ------------------------------------------------------------ //
//  Shadow pass: depth-only dal punto di vista del sole (W1 del piano AAA).
//  Nessun fragment: si scrive solo la depth della shadow map.

vertex VertexOut vertexShadowDepth(uint vid [[vertex_id]],
                                   uint iid [[instance_id]],
                                   constant ShadowUniforms &sh [[buffer(1)]],
                                   const device InstanceData* instances [[buffer(2)]],
                                   constant int32_t &count [[buffer(3)]])
{
    VertexOut out;
    uint vi = vid % 36;
    uint face = vi / 6;
    float3 lp = cubeVerts[vi];
    float3 n = cubeNormals[face];

    float4 world = instances[iid].model * float4(lp, 1.0);
    out.pos = sh.sunViewProj * world;
    out.world = world.xyz;
    out.normal = normalize((instances[iid].model * float4(n, 0.0)).xyz);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = boxScale(instances[iid].model);
    out.uv = float2(0.0);
    return out;
}

// ------------------------------------------------------------ //
//  Città + terra: facciate con finestre e tendaggio, strade con corsie,
//  tetti con unità AC e parapetto, luce solare direzionale, ombre dinamiche.

fragment float4 fragmentMain(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]],
                             texture2d<float> shadowMap [[texture(10)]],
                             sampler shadowSamp [[sampler(1)]],
                             constant ShadowUniforms &shadowU [[buffer(5)]])
{
    float3 n = normalize(in.normal);
    float3 s = max(in.scale, float3(0.001));
    float3 sunDir = normalize(u.sunPre.xyz);
    float sunVis = smoothstep(-0.05, 0.12, sunDir.y);
    // Ombre dinamiche: PCF della shadow map del sole (1 = pieno sole).
    float shad = shadowFactor(in.world, n, shadowMap, shadowSamp, shadowU);
    float dusk = 1.0 - smoothstep(0.05, 0.45, sunDir.y);

    // Terra: asfalto con corsie lungo il corridoio (asse Z) e marciapiedi.
    if (n.y > 0.9 && in.scale.y < 2.5) {
        float2 w = in.world.xz;
        float lane = abs(w.x) < 9.0 ? 1.0 : 0.0;          // carreggiata |x| < 9 m
        float3 asphalt = float3(0.10, 0.105, 0.12) * (0.85 + 0.3 * valueNoise2(w));
        float3 sidewalk = float3(0.52, 0.52, 0.54) * (0.9 + 0.2 * valueNoise2(w * 0.9));
        float3 col = mix(sidewalk, asphalt, lane);

        if (lane > 0.5) {
            // Corsia centrale tratteggiata + bordi laterali (w.y = asse Z).
            float dashes = step(0.5, fract(w.y / 12.0));
            float center = smoothstep(0.35, 0.25, abs(w.x)) * dashes;
            float edges = smoothstep(0.5, 0.35, abs(abs(w.x) - 7.5));
            float3 paint = float3(0.85, 0.85, 0.8);
            col = mix(col, paint, max(center, edges) * 0.9);
            // Strisce pedonali ogni 90 m.
            float cw = smoothstep(0.30, 0.45, abs(fract(w.y / 90.0) - 0.5) * 2.0);
            float zebra = step(fract(w.x / 2.0), 0.5) * (1.0 - cw) * step(abs(w.y - round(w.y / 90.0) * 90.0), 3.0);
            col = mix(col, paint, zebra * 0.85);
        } else {
            // Lastre del marciapiede.
            float slabs = step(0.92, fract(w.x / 3.0)) + step(0.92, fract(w.y / 3.0));
            col *= 1.0 - 0.25 * clamp(slabs, 0.0, 1.0);
        }
        // Ombra morbida del sole sull'asfalto + ombre proiettate dagli edifici.
        col *= (0.55 + 0.45 * sunVis) * shad;
        return float4(col, 1.0);
    }

    // Facciata corrente: dimensioni reali (metri).
    float2 fs;
    float2 uv;
    float2 faceId = float2(0);
    if (abs(n.y) > 0.5) {
        fs = s.xz; uv = in.local.xz;
    } else if (abs(n.x) > 0.5) {
        fs = s.zy; uv = in.local.zy;
        faceId = float2(in.normal.x > 0 ? 1 : 2, 0);
    } else {
        fs = s.xy; uv = in.local.xy;
        faceId = float2(in.normal.z > 0 ? 3 : 4, 0);
    }

    float2 cell  = float2(4.0, 3.5);
    float2 glass = float2(2.4, 1.8);
    float2 floorUV = uv + fs * 0.5;
    float2 cellIJ  = floor(floorUV / cell);
    float2 inCell  = fract(floorUV / cell);
    float2 glassUV = inCell * cell / glass;
    bool inGlass = all(glassUV < 1.0);
    float slab = inCell.y > 0.86 ? 1.0 : 0.0;

    float seed = hash12(cellIJ + faceId * 17.17 + floor(in.world.xz * 0.01) * 7.7);
    float lit  = step(0.62, seed);
    float bright = 0.55 + 0.45 * hash12(cellIJ * 1.7 + faceId + 4.2);
    float style = hash13(floor(in.world.xyz * float3(0.013, 0.013, 0.013)));
    float curtain = step(0.72, style);

    float3 base = in.color.rgb;
    float3 col;

    if (abs(n.y) > 0.5) {
        col = base * 0.5 + float3(0.03);                       // tetto grigio
        float ac = step(0.8, hash12(floor(uv * 0.5)));         // unità di condizionamento
        col += float3(0.10) * ac;
        // Parapetto chiaro sul bordo del tetto.
        float border = min(min(fs.x - abs(uv.x), fs.y - abs(uv.y)) * 1.0, 1.0);
        col = mix(float3(0.6, 0.6, 0.62), col, smoothstep(0.0, 1.2, border));
        col *= (0.55 + 0.45 * sunVis) * shad;
    } else {
        float sunSide = max(0.0, dot(n, sunDir)) * sunVis * shad;
        float3 wall = base * (0.34 + 0.50 * sunSide + 0.14 * max(0.0, dot(n, normalize(float3(0.35, 0.5, 0.6)))));
        float3 glassCol = float3(0.06, 0.10, 0.16);
        float3 litCol = mix(float3(1.0, 0.85, 0.55), float3(0.75, 0.9, 1.0),
                            hash12(cellIJ.yx + faceId + 9.1));
        float3 pane = mix(glassCol, litCol * bright * 1.7, lit);

        if (curtain > 0.5) {
            float3 cw = mix(float3(0.10, 0.16, 0.24), float3(0.35, 0.5, 0.68),
                            0.5 + 0.5 * in.local.y);
            pane = mix(cw, litCol * bright * 1.6, lit * 0.85);
            col = pane;
        } else {
            col = mix(wall, pane, inGlass ? 1.0 : 0.0);
            col = mix(col, wall * 0.45, slab);
        }
        // Finestre accese di sera/tramonto: leggero alone caldo.
        col += litCol * lit * bright * dusk * (inGlass || curtain > 0.5 ? 0.5 : 0.0);
    }

    // Illuminazione: riflesso cielo sul vetro con Fresnel (W2 piano AAA):
    // a incidencee radente il vetro diventa quasi uno specchio (F0 ≈ 0.04).
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float cosT = saturate(dot(n, V));
    float fresnel = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);
    float skyRefl = pow(1.0 - abs(n.y), 3.0) * 0.12 + fresnel * 0.22;
    col += float3(0.45, 0.6, 0.9) * skyRefl;

    // Nebbia atmosferica: scompare salendo di quota (Modulo 10: aria più rarefatta).
    float dist = length(u.cameraPosTime.xyz - in.world);
    float altitudeT = saturate((u.cameraPosTime.y - 400.0) / 2200.0);
    float fog = (1.0 - exp(-dist * 0.0011)) * (1.0 - 0.75 * altitudeT);
    float3 fogCol = mix(float3(0.62, 0.74, 0.92), float3(0.85, 0.62, 0.48), dusk * 0.6);
    col = mix(col, fogCol, clamp(fog, 0.0, 0.85));
    return float4(col, 1.0);
}

// Vertex: mesh (buffer interleaved pos3+normal3, stride 6 float)
vertex VertexOut meshVertex(uint vid [[vertex_id]],
                            uint iid [[instance_id]],
                            const device float* vertices [[buffer(0)]],
                            constant FlyUniforms &u [[buffer(1)]],
                            const device InstanceData* instances [[buffer(2)]])
{
    VertexOut out;
    float3 lp = float3(vertices[vid * 6 + 0], vertices[vid * 6 + 1], vertices[vid * 6 + 2]);
    float3 ln = float3(vertices[vid * 6 + 3], vertices[vid * 6 + 4], vertices[vid * 6 + 5]);

    float4 world = instances[iid].model * float4(lp, 1.0);
    out.pos = u.viewProj * world;
    out.world = world.xyz;
    out.normal = normalize((instances[iid].model * float4(ln, 0.0)).xyz);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = float3(1);
    out.uv = float2(0);
    return out;
}

// Mantello: stride 8 float (pos3 + normal3 + uv2), animato dalla CPU.
vertex VertexOut capeVertex(uint vid [[vertex_id]],
                            const device float* vertices [[buffer(0)]],
                            constant FlyUniforms &u [[buffer(1)]],
                            const device InstanceData* instances [[buffer(2)]])
{
    VertexOut out;
    float3 lp = float3(vertices[vid * 8 + 0], vertices[vid * 8 + 1], vertices[vid * 8 + 2]);
    float3 ln = float3(vertices[vid * 8 + 3], vertices[vid * 8 + 4], vertices[vid * 8 + 5]);
    float2 uv = float2(vertices[vid * 8 + 6], vertices[vid * 8 + 7]);

    float4 world = instances[0].model * float4(lp, 1.0);
    out.pos = u.viewProj * world;
    out.world = world.xyz;
    out.normal = normalize((instances[0].model * float4(ln, 0.0)).xyz);
    out.color = instances[0].color;
    out.local = lp;
    out.scale = float3(1);
    out.uv = uv;
    return out;
}

// ------------------------------------------------------------ //
//  Tessuti (tute, pelle, capelli, NPC): luce solare + rim + speculare

fragment float4 fabricFragment(VertexOut in [[stage_in]],
                               constant FlyUniforms &u [[buffer(1)]])
{
    float3 n = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float3 L = normalize(u.sunPre.xyz);
    float sunVis = smoothstep(-0.05, 0.12, L.y);

    float diff = max(0.0, dot(n, L));
    float sky = 0.5 + 0.5 * n.y;                       // luce emisferica dal cielo
    float3 sunTint = mix(float3(1.0, 0.75, 0.55), float3(1.0, 0.96, 0.9), sunVis);
    float3 col = in.color.rgb * (0.30 + 0.80 * diff * sunVis) * (0.75 + 0.35 * sky);
    col += in.color.rgb * 0.12 * sky;                  // rimbalzo ambientale

    // Speculare morbido (tuta e pelle riflettono un po').
    float3 H = normalize(L + V);
    float spec = pow(max(0.0, dot(n, H)), 24.0) * 0.35 * sunVis;
    col += sunTint * spec;

    // Rim light dal cielo: stacca i personaggi dallo sfondo.
    float rim = pow(1.0 - max(0.0, dot(n, V)), 2.4) * 0.30;
    col += float3(0.5, 0.65, 0.95) * rim;

    // Alpha > 1 marca materiali emissivi (emblema).
    if (in.color.a > 1.5) {
        col = in.color.rgb * 2.2;
    }

    float dist = length(u.cameraPosTime.xyz - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    col = mix(col, float3(0.62, 0.74, 0.92), clamp(fog, 0.0, 0.85) * 0.7);
    return float4(col, 1.0);
}

// Nuvole: blocchi bianchi dai bordi morbidi (smussati via local coord).
fragment float4 cloudFragment(VertexOut in [[stage_in]],
                              constant FlyUniforms &u [[buffer(1)]])
{
    float3 n = normalize(in.normal);
    float diff = 0.7 + 0.3 * max(0.0, dot(n, normalize(u.sunPre.xyz)));
    float3 col = float3(1.0, 1.0, 1.02) * diff;
    // Bordo morbido del blocco: le facce laterali sfumano verso trasparente.
    float edge = 1.0 - max(abs(in.local.x), abs(in.local.z));
    float edgeFade = smoothstep(0.0, 0.45, edge);
    float dist = length(u.cameraPosTime.xyz - in.world);
    float fog = 1.0 - exp(-dist * 0.0012);
    col = mix(col, float3(0.62, 0.74, 0.92), clamp(fog, 0.0, 1.0) * 0.9);
    return float4(col, 0.62 * edgeFade);
}

// Glow additivo: anelli, laser, particelle, boost.
fragment float4 glowFragment(VertexOut in [[stage_in]],
                             constant FlyUniforms &u [[buffer(1)]])
{
    float edge = 1.0 - abs(in.local.y);
    float a = in.color.a * (0.35 + 0.65 * edge);
    float3 col = in.color.rgb * (1.5 + edge);
    float dist = length(u.cameraPosTime.xyz - in.world);
    float fog = 1.0 - exp(-dist * 0.0011);
    col = mix(col, float3(0.62, 0.74, 0.92), clamp(fog, 0.0, 0.85) * (1.0 - a));
    return float4(col * a, a);
}

// Cielo procedurale: quad full-screen disegnato con depth always prima della
// scena; la direzione di vista viene ricostruita via inversa view-proj.
fragment float4 skyFragment(PostOut in [[stage_in]],
                            constant FlyUniforms &u [[buffer(1)]])
{
    float4 farP = u.invViewProj * float4(in.uv * 2.0 - 1.0, 1.0, 1.0);
    float3 dir = normalize(farP.xyz / farP.w - u.cameraPosTime.xyz);
    float altT = saturate((u.cameraPosTime.y - 400.0) / 2200.0);
    float3 col = skyColor(dir, normalize(u.sunPre.xyz), altT, u.cameraPosTime.w);
    return float4(col, 1.0);
}

// ------------------------------------------------------------ //
//  Post-process: bright pass → blur separabile → composite (tonemap ACES)

// Quad full-screen: 6 vertici senza buffer (posizioni generate da vid).
vertex PostOut postVertex(uint vid [[vertex_id]])
{
    float2 p = float2(float(vid & 1), float(vid >> 1));   // (0,0)(1,0)(0,1)(1,0)(0,1)(1,1)
    PostOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

fragment float4 brightPassFrag(PostOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 c = tex.sample(s, in.uv).rgb;
    float l = max(max(c.r, c.g), c.b);
    float t = smoothstep(0.85, 1.6, l);
    return float4(c * t, 1.0);
}

fragment float4 blurFrag(PostOut in [[stage_in]],
                         texture2d<float> tex [[texture(0)]],
                         constant float2 &dirTexel [[buffer(4)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 texel = float2(1.0 / float(tex.get_width()), 1.0 / float(tex.get_height()));
    float2 o1 = dirTexel.xy * texel * 1.3846153846;
    float2 o2 = dirTexel.xy * texel * 3.2307692308;
    float3 acc = tex.sample(s, in.uv).rgb * 0.2270270270;
    acc += tex.sample(s, in.uv + o1).rgb * 0.3162162162;
    acc += tex.sample(s, in.uv - o1).rgb * 0.3162162162;
    acc += tex.sample(s, in.uv + o2).rgb * 0.0702702703;
    acc += tex.sample(s, in.uv - o2).rgb * 0.0702702703;
    return float4(acc, 1.0);
}

fragment float4 compositeFrag(PostOut in [[stage_in]],
                              texture2d<float> scene [[texture(0)]],
                              texture2d<float> bloom [[texture(1)]],
                              constant FlyUniforms &u [[buffer(1)]])
{
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float3 col = scene.sample(s, in.uv).rgb;
    float3 b = bloom.sample(s, in.uv).rgb;

    // Bloom additivo + tonemap ACES (filmico,Highlights che non bruciano).
    float3 x = col + b * 0.55;
    x = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);

    // Vignetta leggera + grana filmica sottilissima (maschera il banding).
    float2 q = in.uv - 0.5;
    float vig = 1.0 - dot(q, q) * 0.55;
    float grain = (hash12(in.uv * u.bufferSizePad.xy + fract(u.cameraPosTime.w) * 61.7) - 0.5) * 0.012;
    return float4(clamp(x * vig + grain, 0.0, 1.0), 1.0);
}

// ------------------------------------------------------------ //
//  PBR città (W2 del piano AAA): Cook-Torrance + ombre dinamiche. Pipeline
//  opzionale: il Renderer la costruisce solo se la libreria espone questi
//  simboli; in caso contrario resta attivo fragmentMain (Lambert + ombre).

vertex VertexOut vertexMainPBR(uint vid [[vertex_id]],
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
    out.normal = normalize((instances[iid].model * float4(n, 0.0)).xyz);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = boxScale(instances[iid].model);
    out.uv = float2(fract(world.x * 0.1), fract(world.z * 0.1));
    return out;
}

fragment float4 fragmentMainCityPBR(VertexOut in [[stage_in]],
                                    constant FlyUniforms &u [[buffer(1)]],
                                    texture2d<float> shadowMap [[texture(10)]],
                                    sampler shadowSamp [[sampler(1)]],
                                    constant ShadowUniforms &shadowU [[buffer(5)]])
{
    float3 n = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float3 L = normalize(u.sunPre.xyz);
    float sunVis = smoothstep(-0.05, 0.12, L.y);
    float shad = shadowFactor(in.world, n, shadowMap, shadowSamp, shadowU);

    float3 baseColor = in.color.rgb;
    float roughness = 0.7;
    float metallic = 0.0;
    cityMaterial(baseColor, in.world, n, roughness, metallic);

    // Cook-Torrance moltiplicato per l'energia solare e le ombre PCF.
    float3 lit = cookTorranceBRDF(n, V, L, roughness, metallic, baseColor)
                 * max(0.0, dot(n, L)) * sunVis * shad * float3(1.0, 0.95, 0.8);
    // Ambient emisferico: cielo sopra, asfalto sotto (attenuato in ombra).
    float3 ambient = baseColor * mix(float3(0.03, 0.04, 0.10), float3(0.10, 0.12, 0.16),
                                     0.5 + 0.5 * n.y) * (0.6 + 0.4 * shad);
    float3 col = lit + ambient;

    // Riflesso cielo sul vetro + nebbia atmosferica (come fragmentMain).
    float skyRefl = pow(1.0 - abs(n.y), 3.0) * 0.12 * (1.0 - metallic * 0.5);
    col += float3(0.45, 0.6, 0.9) * skyRefl;
    float dist = length(u.cameraPosTime.xyz - in.world);
    float altitudeT = saturate((u.cameraPosTime.y - 400.0) / 2200.0);
    float dusk = 1.0 - smoothstep(0.05, 0.45, L.y);
    float fog = (1.0 - exp(-dist * 0.0011)) * (1.0 - 0.75 * altitudeT);
    float3 fogCol = mix(float3(0.62, 0.74, 0.92), float3(0.85, 0.62, 0.48), dusk * 0.6);
    col = mix(col, fogCol, clamp(fog, 0.0, 0.85));
    return float4(col, 1.0);
}

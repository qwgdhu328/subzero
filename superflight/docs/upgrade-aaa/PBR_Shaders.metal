// ============================================================================
// PBR SHADER IMPLEMENTATION — SuperFlight
// ============================================================================
// Shader fisicamente corretti per finestre, acciaio, mantello, Superman
// Copy-paste ready per Shaders.metal
//
// Uso: substituite fragmentMainCity con fragmentMainCityPBR
// Aggiungi texture per roughness/metallic maps
// ============================================================================

#include <metal_stdlib>
using namespace metal;

// Layout PBR-specifico
struct PBRMaterial {
    float3 albedo;         // colore base [0,1]
    float roughness;       // 0 = lucido, 1 = opaco
    float metallic;        // 0 = dielettrico, 1 = metal
    float normalStrength;  // 0.5..2.0
    float ambientOcclusion;// 0..1
};

struct FlyUniforms {
    float4x4 viewProj;
    float4x4 invViewProj;
    float4 cameraPosTime;
    float4 fwdAspect;
    float4 sunPre;          // xyz = sun direction, w = scale
    float4 bufferSizePad;
};

// ============================================================================
// MATH UTILITIES
// ============================================================================

// Fresnel-Schlick: calcola il rapporto riflesso/rifratto
inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Distribution GGX (Trowbridge-Reitz): microfacet model
inline float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    denom = M_PI_F * denom * denom;
    return a2 / max(denom, 0.0001);
}

// Geometry function: Smith-Schlick (G term in Cook-Torrance BRDF)
inline float geometrySchlickGGX(float NdotV, float roughness) {
    float r = (roughness + 1.0);
    float k = (r * r) / 8.0;
    float num = NdotV;
    float denom = NdotV * (1.0 - k) + k;
    return num / denom;
}

inline float geometrySmith(float NdotV, float NdotL, float roughness) {
    float ggx2 = geometrySchlickGGX(NdotV, roughness);
    float ggx1 = geometrySchlickGGX(NdotL, roughness);
    return ggx1 * ggx2;
}

// ============================================================================
// NORMAL MAPPING
// ============================================================================

// Estrai normal dal mappa normale (tangent space)
inline float3 getNormalFromMap(float3 normalMap, float3 N, float3 worldPos, float2 uv) {
    // Tangent space basis
    float3 Q1 = dfdx(worldPos);
    float3 Q2 = dfdy(worldPos);
    float2 st1 = dfdx(uv);
    float2 st2 = dfdy(uv);
    
    float3 N3 = normalize(N);
    float3 T = normalize(Q1 * st2.y - Q2 * st1.y);
    float3 B = -normalize(cross(N3, T));
    float3x3 TBN = float3x3(T, B, N3);
    
    // Decodifica normal map da [0,1] a [-1,1]
    return normalize(TBN * normalize(normalMap * 2.0 - 1.0));
}

// ============================================================================
// PROCEDRAL MATERIAL GENERATION (runtime)
// ============================================================================

// Generate normal map proceduralmente (per edifici, strade)
inline float3 proceduralNormalMap(float3 worldPos, float2 uv) {
    // Bump mapping semplice: usa worldPos per variazione
    float h1 = sin(worldPos.x * 0.5) * cos(worldPos.z * 0.3);
    float h2 = sin(worldPos.z * 0.7) * cos(worldPos.x * 0.2);
    
    float3 n = normalize(float3(dfdx(h1), 1.0, dfdz(h1)));
    return n;
}

// Roughness map per zone (finestre = smooth, cemento = rough)
inline float getRoughnessValue(float3 color, float2 uv, float3 worldPos) {
    // Se è finestra (colore scuro/blu), roughness bassa
    float luminance = dot(color, float3(0.299, 0.587, 0.114));
    if(luminance < 0.3) {
        // Finestra
        return 0.1 + 0.05 * sin(worldPos.x * 0.1) * cos(worldPos.y * 0.1);
    } else {
        // Muratura/cemento
        return 0.7 + 0.2 * sin(uv.x * 10.0) * cos(uv.y * 10.0);
    }
}

// Metallic map
inline float getMetallicValue(float3 color, float3 worldPos) {
    // Tetti e acciaio = metallico
    float luminance = dot(color, float3(0.299, 0.587, 0.114));
    
    // Griglie AC, antenne: metallico
    float gridPattern = abs(sin(worldPos.x * 0.3)) > 0.8 ? 1.0 : 0.0;
    
    return mix(0.0, 0.8, gridPattern);  // 0 = dielettrico, 0.8 = metal
}

// ============================================================================
// COOK-TORRANCE BRDF (Physically Based Rendering)
// ============================================================================

// Calcola la componente speculare del BRDF
inline float3 cookTorranceBRDF(
    float3 N, float3 V, float3 L,
    float roughness, float metallic,
    float3 baseColor)
{
    float3 H = normalize(V + L);
    
    float NdotV = max(dot(N, V), 0.001);
    float NdotL = max(dot(N, L), 0.0);
    float NdotH = max(dot(N, H), 0.0);
    float HdotV = max(dot(H, V), 0.0);
    
    // F0 (fresnel at 0 degrees): 0.04 per dielettrici, albedo per metalli
    float3 F0 = mix(float3(0.04), baseColor, metallic);
    
    // Fresnel term
    float3 F = fresnelSchlick(HdotV, F0);
    
    // Distribution
    float D = distributionGGX(NdotH, roughness);
    
    // Geometry
    float G = geometrySmith(NdotV, NdotL, roughness);
    
    // Cook-Torrance specular
    float3 numerator = D * F * G;
    float denominator = 4.0 * NdotV * NdotL + 0.001;
    float3 specular = numerator / denominator;
    
    // kS = F (frazione speculare), kD = 1 - kS (frazione diffusa)
    float3 kS = F;
    float3 kD = float3(1.0) - kS;
    kD *= 1.0 - metallic;  // i metalli non hanno componente diffusa
    
    // Lambertian BRDF per la parte diffusa
    float3 diffuse = kD * baseColor / M_PI_F;
    
    // Combina diffuso + speculare
    return diffuse + specular;
}

// ============================================================================
// TEXTURE GENERATION (city-specific)
// ============================================================================

// Finestre realistiche su edifici
inline float4 generateWindowPattern(float3 worldPos, float2 uv, float3 normal) {
    // Grid di finestre
    float2 gridUV = fract(worldPos.xy * 0.05);
    float2 gridCell = floor(worldPos.xy * 0.05);
    
    // Finestra è rettangolo 0.8 × 0.6 nella cella
    float windowX = step(0.05, gridUV.x) * step(gridUV.x, 0.85);
    float windowY = step(0.1, gridUV.y) * step(gridUV.y, 0.9);
    float windowMask = windowX * windowY;
    
    // Colore: blu scuro (interno stanza) o giallo (luce accesa casuale)
    float lightprob = fract(sin(dot(gridCell, float2(12.9898, 78.233))) * 43758.5453);
    float3 windowColor = mix(
        float3(0.05, 0.15, 0.3),    // spento (blu scuro)
        float3(1.0, 0.95, 0.7),     // acceso (giallo caldo)
        lightprob
    );
    
    // Se è finestra, usa colore finestra; altrimenti mattone
    float3 brickColor = float3(0.7, 0.6, 0.5);
    float3 color = mix(brickColor, windowColor, windowMask);
    
    return float4(color, windowMask);
}

// Strade con corsie
inline float4 generateRoad(float3 worldPos) {
    // Asfalto di base
    float3 asphaltColor = float3(0.15, 0.15, 0.18);
    
    // Corsie bianche ogni 10 m (Z direction)
    float lanePattern = mod(worldPos.z, 10.0) < 0.5 ? 1.0 : 0.0;
    float3 lineColor = float3(0.9);
    
    float3 roadColor = mix(asphaltColor, lineColor, lanePattern * 0.7);
    
    return float4(roadColor, 1.0);
}

// ============================================================================
// VERTEX SHADER (nessun cambio rispetto a quello originale)
// ============================================================================

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
    out.uv = float2(fract(out.world.x * 0.1), fract(out.world.z * 0.1));
    
    return out;
}

// ============================================================================
// FRAGMENT SHADER PBR (MAIN)
// ============================================================================

fragment float4 fragmentMainCityPBR(
    VertexOut in [[stage_in]],
    constant FlyUniforms &u [[buffer(1)]],
    texture2d<float> shadowMapTex [[texture(10)]],
    sampler shadowSamp [[sampler(1)]],
    constant ShadowUniforms &shadowUni [[buffer(5)]],
    texture2d<float> normalMapTex [[texture(2)]],
    sampler normalSamp [[sampler(2)]])
{
    // ----- MATERIAL SETUP -----
    
    float3 N = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float3 L = normalize(u.sunPre.xyz);
    
    // Determina se è strada o edificio
    bool isRoad = abs(in.local.y) < 0.01;  // y ≈ 0 = ground/road
    bool isWindow = in.color.r < 0.3 && in.color.g < 0.3;  // colore scuro = finestra
    
    // Colore base
    float4 baseTexture;
    if(isRoad) {
        baseTexture = generateRoad(in.world);
    } else if(isWindow) {
        baseTexture = generateWindowPattern(in.world, in.uv, N);
    } else {
        // Edificio standard
        baseTexture = float4(in.color.rgb, 1.0);
    }
    
    float3 baseColor = baseTexture.rgb;
    
    // Roughness e Metallic
    float roughness = getRoughnessValue(baseColor, in.uv, in.world);
    float metallic = getMetallicValue(baseColor, in.world);
    float ao = 1.0;  // ambient occlusion (potrebbe provenire da texture)
    
    // Normal mapping (opzionale per edifici lisci)
    // N = getNormalFromMap(normalMapTex.sample(normalSamp, in.uv).rgb, N, in.world, in.uv);
    
    // ----- PBR CALCULATION -----
    
    // Cook-Torrance BRDF
    float3 Lo = cookTorranceBRDF(N, V, L, roughness, metallic, baseColor);
    
    // Illuminazione solare
    float NdotL = max(dot(N, L), 0.0);
    
    // SHADOW SAMPLING (da shadow mapping pass)
    float shadow = 1.0;
    {
        float4 shadowCoord4 = shadowUni.sunViewProj * float4(in.world, 1.0);
        float3 shadowCoord = shadowCoord4.xyz / shadowCoord4.w;
        shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
        shadowCoord.z -= shadowUni.shadowBias;
        
        if(shadowCoord.x >= 0 && shadowCoord.x <= 1 &&
           shadowCoord.y >= 0 && shadowCoord.y <= 1) {
            float texelSize = 1.0 / shadowUni.shadowResolution;
            shadow = 0.0;
            for(int x = -1; x <= 1; ++x) {
                for(int y = -1; y <= 1; ++y) {
                    float2 uv = shadowCoord.xy + float2(x, y) * texelSize;
                    float depthShadow = shadowMapTex.sample(shadowSamp, uv).r;
                    shadow += (depthShadow < shadowCoord.z) ? 0.0 : 1.0;
                }
            }
            shadow /= 9.0;
        }
    }
    
    float3 sunColor = float3(1.0, 0.95, 0.8);  // slightly warm sunlight
    float3 sunLight = sunColor * NdotL * shadow;
    
    // Illuminazione totale
    float3 result = Lo * sunLight;
    
    // Ambient (semplice)
    float3 ambientColor = mix(
        float3(0.03, 0.04, 0.10),  // cielo (blu)
        float3(0.10, 0.06, 0.03),  // terreno (marrone)
        0.5
    );
    result += ambientColor * baseColor * ao * 0.3;
    
    // ----- TONE MAPPING + GAMMA -----
    
    // ACES tone mapping (approssimato)
    float3 aces = result;
    aces = aces / (aces + float3(0.0245786));  // fit
    aces = pow(aces, float3(1.0 / 2.2));      // gamma correction
    
    return float4(aces, 1.0);
}

// ============================================================================
// SUPERMAN / CHARACTER SHADER (mantello + pelle)
// ============================================================================

fragment float4 fragmentSuperManPBR(
    VertexOut in [[stage_in]],
    constant FlyUniforms &u [[buffer(1)]],
    texture2d<float> mantelloNormal [[texture(3)]],
    sampler normalSamp [[sampler(3)]])
{
    float3 N = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float3 L = normalize(u.sunPre.xyz);
    
    // Mantello: rosso brillante, leggermente metallico
    float3 mantelloColor = float3(0.85, 0.05, 0.05);
    float mantelloRoughness = 0.3;  // lucido come tessuto satinato
    float mantelloMetallic = 0.0;   // cloth, non metal
    
    // Corpo: pelle flesh tone
    bool isCape = in.color.r > in.color.b;  // mantello è più rosso
    
    float3 baseColor = isCape ? mantelloColor : float3(0.95, 0.75, 0.65);  // pelle
    float roughness = isCape ? mantelloRoughness : 0.5;
    float metallic = isCape ? mantelloMetallic : 0.0;
    
    // Normal mapping su mantello
    if(isCape) {
        float3 normalTex = mantelloNormal.sample(normalSamp, in.uv).rgb;
        // N = getNormalFromMap(normalTex, N, in.world, in.uv);
    }
    
    // PBR Cook-Torrance
    float3 Lo = cookTorranceBRDF(N, V, L, roughness, metallic, baseColor);
    
    float NdotL = max(dot(N, L), 0.0);
    float3 result = Lo * NdotL * float3(1.0, 0.95, 0.8);
    
    // Sottosuperficie leggera (pelle)
    if(!isCape) {
        float backLight = pow(max(0.0, -dot(N, L)), 2.0);
        result += baseColor * backLight * 0.15;
    }
    
    // Ambient
    result += baseColor * 0.2;
    
    // Tonemap
    result = result / (result + float3(0.0245786));
    result = pow(result, float3(1.0 / 2.2));
    
    return float4(result, 1.0);
}

// ============================================================================
// SIMPLE PBR FOR PARTICLES / ANELLI
// ============================================================================

fragment float4 fragmentAneloPBR(
    VertexOut in [[stage_in]],
    constant FlyUniforms &u [[buffer(1)]])
{
    // Anelli: azzurri, molto metallici e specular
    float3 N = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - in.world);
    float3 L = normalize(u.sunPre.xyz);
    
    float3 baseColor = float3(0.1, 0.6, 1.0);  // azzurro
    float roughness = 0.1;  // super lucido
    float metallic = 1.0;   // full metal
    
    float3 Lo = cookTorranceBRDF(N, V, L, roughness, metallic, baseColor);
    
    float NdotL = max(dot(N, L), 0.0);
    float3 result = Lo * NdotL * 2.0;  // emissive boost
    
    // Glow additivo
    result += baseColor * 0.5;
    
    return float4(result, in.color.a);
}

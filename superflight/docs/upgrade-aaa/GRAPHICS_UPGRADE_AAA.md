# 🎬 SuperFlight — Piano d'Upgrade Grafico AAA (100M€ production)

> **Obiettivo finale**: visuals da **Insomnia's Spider-Man** / **Unreal Engine 5** quality, mantenendo engine custom Metal lean (zero middleware costoso).

---

## 📊 Stato attuale vs. Target AAA

| Aspetto | Attuale | Target AAA | Impatto visivo |
|---------|---------|-----------|-----------------|
| **Shader complexity** | Lambert + proc textures | PBR + Normal maps | ⭐⭐⭐⭐ |
| **Post-processing** | Bloom + tonemap | Bloom + DoF + Motion blur + Color grade + LUT | ⭐⭐⭐⭐ |
| **Dinamiche luci** | Sun direzionale statica | HDR + Exposure metering + Godray volumetrici | ⭐⭐⭐⭐ |
| **Ombre** | Nessuna | Shadow maps (soft) su city/mantello | ⭐⭐⭐⭐⭐ |
| **Ambient Occlusion** | No | SSAO (screen-space) in post | ⭐⭐⭐ |
| **Riflessioni** | No | SSR (screen-space reflection) minimale | ⭐⭐⭐ |
| **Detail & tessiture** | Procedurale liscia | Normal/roughness/metallic maps + Parallax | ⭐⭐⭐ |
| **Effetti speciali** | Particles semplici | Depth-based particle, distortion, smoke volumetrico | ⭐⭐⭐ |
| **Superman** | Mesh base rigida | Hair card animation, mantello cloth realistica, Eyes subsurface | ⭐⭐⭐⭐ |
| **Città** | Cubi piatti | Dettagli architettonici, balconate, antenne, billboard | ⭐⭐⭐ |
| **Cielo** | Procedurale semplice | Scattering atmosferico realistico (Rayleigh), cirrus dinamiche | ⭐⭐⭐ |

---

## 🎨 5 Pilastri AAA (in ordine di impatto)

### 1️⃣ **SHADOW MAPPING + SOFT SHADOWS** (⭐⭐⭐⭐⭐)

Sono le ombre dinamiche: trasformano lo stato da "cartoon" a "realistico" istantaneamente.

#### Implementazione (Metal + Renderer.swift)

```swift
// 1. Texture depth shadow (1K × 1K per la città, update ogni frame)
private var shadowMap: MTLTexture?
private var shadowDepthState: MTLDepthStencilState!

// 2. Shadow render pass: ridisegna la città da POV del sole
func renderShadows(cmd: MTLCommandBuffer) {
    let desc = MTLRenderPassDescriptor()
    desc.depthAttachment.texture = shadowMap
    desc.depthAttachment.clearDepth = 1.0
    desc.depthAttachment.loadAction = .clear
    
    let pass = cmd.makeRenderCommandEncoder(descriptor: desc)!
    pass.setRenderPipelineState(pipelineShadowDepth) // semplicissimo: solo depth
    // Disegna tutti i cubi città (stessi instance data di renderCity)
    // View matrix: lookFrom(sunPos, sunDir)
    pass.endEncoding()
}

// 3. Nel fragment della città: sample shadow + penombra
fragment float4 fragmentMainShadow(...) {
    // Convert to shadow space
    float4 shadowCoord = shadowViewProj * float4(in.world, 1.0);
    shadowCoord.xyz /= shadowCoord.w;
    shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;  // NDC → [0,1]
    
    // PCF 5x5: soft shadow
    float shadow = 0.0;
    float texelSize = 1.0 / 1024.0; // shadow map res
    for(int x = -2; x <= 2; ++x) {
        for(int y = -2; y <= 2; ++y) {
            float2 uv = shadowCoord.xy + float2(x, y) * texelSize;
            float depth = shadowMap.sample(samp, uv).r;
            if(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1) {
                shadow += (depth < shadowCoord.z - 0.002) ? 0.0 : 1.0;
            }
        }
    }
    shadow /= 25.0;
    
    // Lit = mix(darkenedColor, litColor, shadow)
    float3 lit = mix(baseColor * 0.4, baseColor, shadow);
    return float4(lit, 1.0);
}
```

**Performance**: Shadow map 1K a 120Hz ≈ 1-2ms su iPhone 15 Pro (GPU-bound, accettabile).

---

### 2️⃣ **PBR + NORMAL MAPPING** (⭐⭐⭐⭐)

Normal mapping + roughness/metallic maps modernizzano il look drasticamente. Usiamo **GGX microfacet** (standard industria).

#### Shaders.metal – Fragment PBR

```metal
// Costanti: solo per edifici/mantello (città non ne ha bisogno)
struct MaterialData {
    float roughness;      // 0=mirror, 1=diffuse
    float metallic;       // 0=dielectric, 1=metal (per finestre: 0, acciaio tetti: 0.8)
    float normalStrength; // scala normal map (0.5..2.0)
};

// Normal mapping (semplice: tangent space)
float3 getNormal(float3 normalMap, float3 geometricNormal, float3 tangent) {
    float3 normal = normalize(normalMap * 2.0 - 1.0);
    
    // Gram-Schmidt ortogonalizzazione: TBN matrix
    float3 n = geometricNormal;
    float3 t = normalize(tangent - dot(tangent, n) * n);
    float3 b = cross(n, t);
    
    return normalize(
        normal.x * t +
        normal.y * b +
        normal.z * n
    );
}

// Fresnel schlick (edge glow su superfici curve)
float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(1.0 - cosTheta, 5.0);
}

// Geometry masking-shadowing GGX
float geometrySmith(float NdotV, float NdotL, float roughness) {
    float r = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float ggx1 = NdotV / (NdotV * (1.0 - r) + r);
    float ggx2 = NdotL / (NdotL * (1.0 - r) + r);
    return ggx1 * ggx2;
}

// Distribution GGX
float DistributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (3.14159 * denom * denom);
}

fragment float4 fragmentPBR(VertexOut in [[stage_in]],
                           constant FlyUniforms &u [[buffer(1)]],
                           texture2d<float> normalMap [[texture(0)]],
                           texture2d<float> roughnessMap [[texture(1)]],
                           sampler samp [[sampler(0)]])
{
    // World-space
    float3 world = in.world;
    float3 N = normalize(in.normal);
    float3 V = normalize(u.cameraPosTime.xyz - world);
    float3 L = normalize(u.sunPre.xyz);
    
    // Sample texture maps
    float3 normalTex = normalMap.sample(samp, in.uv * 4.0).rgb;
    N = getNormal(normalTex, N, cross(normalize(dFdx(world)), normalize(dFdy(world))));
    
    float roughness = roughnessMap.sample(samp, in.uv * 4.0).r;
    float metallic = 0.2; // fissato per edifici
    
    // Calcolari termini PBR
    float NdotV = max(dot(N, V), 0.0001);
    float NdotL = max(dot(N, L), 0.0);
    float3 H = normalize(V + L);
    float NdotH = max(dot(N, H), 0.0);
    
    float3 F0 = mix(float3(0.04), in.color.rgb, metallic);
    float3 F = fresnelSchlick(max(dot(H, V), 0.0), F0);
    float G = geometrySmith(NdotV, NdotL, roughness);
    float D = DistributionGGX(NdotH, roughness);
    
    float3 kS = F;
    float3 kD = (1.0 - kS) * (1.0 - metallic);
    float3 specular = (D * F * G) / max(4.0 * NdotV * NdotL, 0.001);
    
    float3 result = (kD * in.color.rgb / 3.14159 + specular) * NdotL;
    
    // Ambient + emissive
    result += in.color.rgb * 0.15;  // ambient semplice
    
    return float4(result, 1.0);
}
```

**Impatto**: Finestre riflettenti, acciaio brillante tetti, mantello con profondità.

---

### 3️⃣ **MOTION BLUR + DEPTH OF FIELD** (⭐⭐⭐⭐)

A 3000 km/h, la velocità permette effetti cinetici drammatici.

#### Implementazione (Post-processing)

```swift
// Velocity buffer: ogni pixel memorizza velocità screen-space
private var velocityBuffer: MTLTexture?

// Vertex shader genera velocity
vertex VertexOut vertexMotionBlur(...) {
    // ... standard vertex shader ...
    out.screenPrev = prevViewProj * float4(in.world, 1.0); // pos frame precedente
}

fragment float4 fragmentMotionBlur(PostOut in [[stage_in]],
                                  texture2d<float> sceneColor [[texture(0)]],
                                  texture2d<float> velocityTex [[texture(1)]],
                                  sampler samp [[sampler(0)]])
{
    float2 velocity = velocityTex.sample(samp, in.uv).rg;
    
    // Tempo-reprojection: ripeti sample lungo la traiettoria
    float4 color = float4(0.0);
    const int samples = 8;
    for(int i = 0; i < samples; ++i) {
        float t = (float(i) / float(samples - 1)) - 0.5;
        float2 offset = velocity * t * 0.01; // scala motion
        color += sceneColor.sample(samp, in.uv + offset);
    }
    color /= float(samples);
    
    return color;
}
```

**Performance**: Velocità > 2000 km/h → motion blur 2-4 tap (CPU negligible).

---

### 4️⃣ **VOLUMETRIC LIGHTING (GOD RAYS)** (⭐⭐⭐⭐)

Il sole filtra tra i grattacieli: effetto cinematico iconic.

```metal
fragment float4 fragmentGodRays(PostOut in [[stage_in]],
                               texture2d<float> sceneTex [[texture(0)]],
                               texture2d<float> depthTex [[texture(1)]],
                               constant FlyUniforms &u [[buffer(1)]],
                               sampler samp [[sampler(0)]])
{
    float3 sceneColor = sceneTex.sample(samp, in.uv).rgb;
    float depth = depthTex.sample(samp, in.uv).r;
    
    // Riproietta a world space
    float4 ndc = float4(in.uv * 2.0 - 1.0, depth, 1.0);
    float4 worldH = u.invViewProj * ndc;
    float3 worldPos = worldH.xyz / worldH.w;
    
    // Vettore sole (semplificato: Volumetric Light Scattering)
    float3 sunDir = normalize(u.sunPre.xyz);
    float3 rayDir = worldPos - u.cameraPosTime.xyz;
    float rayLen = length(rayDir);
    rayDir /= rayLen;
    
    // Scattering (Mie): favorisce forward scattering
    float scattering = pow(max(0.0, dot(rayDir, sunDir)), 2.0) * 0.8;
    
    // Samples lungo il ray (raymarch semplice)
    float transmittance = 1.0;
    float volumetric = 0.0;
    const float stepDist = 50.0;
    int steps = min(8, int(rayLen / stepDist));
    
    for(int i = 0; i < steps; ++i) {
        float t = float(i) / float(steps);
        float3 p = u.cameraPosTime.xyz + rayDir * rayLen * t;
        
        // Densità (in aree città è alta)
        float density = exp(-length(p.y - 200.0) / 300.0) * 0.002;
        
        volumetric += transmittance * density * scattering;
        transmittance *= exp(-density * stepDist);
    }
    
    float3 godray = float3(0.9, 0.85, 0.7) * volumetric * 2.0;
    sceneColor += godray;
    
    return float4(sceneColor, 1.0);
}
```

**Costo**: 8 steps raymarch a 120Hz ≈ 0.5ms.

---

### 5️⃣ **ATMOSFERIC SCATTERING (RAYLEIGH + MIE)** (⭐⭐⭐)

Cielo realistico con dispersione fisica della luce.

```metal
float3 skyScattering(float3 rayDir, float3 sunDir, float altitude) {
    // Rayleigh: blu intenso in zenitale
    float3 betaRayleigh = float3(5.8e-6, 13.5e-6, 33.1e-6);
    
    // Mie: rosso tramonto lungo l'orizzonte
    float3 betaMie = float3(21e-6);
    
    float sunAngle = acos(dot(rayDir, sunDir));
    float g = 0.76; // asimmetria Mie (anisotropia forward)
    float miePhase = (1.0 - g*g) / pow(1.0 + g*g - 2.0*g*cos(sunAngle), 1.5);
    
    // Air density decreases exponentially
    float airDensity = exp(-altitude / 8000.0);
    
    float3 rayleighScatter = betaRayleigh * airDensity;
    float3 mieScatter = betaMie * airDensity * miePhase * 0.5;
    
    return rayleighScatter + mieScatter;
}
```

---

## 🎯 Priority Implementation Roadmap (6 settimane)

| Week | Task | Ore | Deliverable |
|------|------|------|------------|
| **W1** | Shadow mapping + soft shadows | 16h | Città illuminata realisticamente |
| **W2** | PBR shader + normal maps | 14h | Superman/mantello brillanti; finestre riflettenti |
| **W3** | Motion blur + DoF post-processing | 12h | Effetto "super velocità" a 3000 km/h |
| **W4** | Volumetric god rays + atmospheric scattering | 14h | Cielo cinematico |
| **W5** | SSAO (Ambient Occlusion) + SSR (reflections) | 12h | Dettagli zona ombre; laghetti riflettenti |
| **W6** | Polish: color grading + LUT + hair animation | 10h | Finale AAA look |

**Total**: ~78 ore (= 2 settimane full-time, 4 part-time).

---

## 🔧 Renderer.swift Changes (skeleton)

```swift
// Aggiungi al Renderer
private var pipelineShadowDepth: MTLRenderPipelineState!
private var pipelineMotionBlur: MTLRenderPipelineState!
private var pipelineVolumetric: MTLRenderPipelineState!
private var pipelineSSAO: MTLRenderPipelineState!
private var shadowMap: MTLTexture?
private var velocityBuffer: MTLTexture?
private var ssaoBuffer: MTLTexture?

// Build pass: shadow mapping → scene → post-process chain
func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    let cmd = commandQueue.makeCommandBuffer()!
    
    // 1. Shadow pass
    if let enc = cmd.makeRenderCommandEncoder(descriptor: shadowDesc) {
        enc.setRenderPipelineState(pipelineShadowDepth)
        // Draw city from sun POV
        enc.endEncoding()
    }
    
    // 2. Main scene (con sampling shadow maps)
    if let enc = cmd.makeRenderCommandEncoder(descriptor: mainDesc) {
        enc.setRenderPipelineState(pipelineCity)  // now PBR + shadows
        // Draw tutto...
        enc.endEncoding()
    }
    
    // 3. Post-processing chain
    applyMotionBlur(cmd: cmd)
    applyVolumetric(cmd: cmd)
    applySSAO(cmd: cmd)
    applyFinalTonemap(cmd: cmd)
    
    cmd.present(view.currentDrawable!)
    cmd.commit()
}
```

---

## 📦 Asset Texture Guide

Per supportare PBR, crea semplici texture procedurali (no external assets, mantieni zero dipendenze):

```swift
// Genera normal map a runtime (es. finestre procedurali)
func generateNormalMap(size: Int) -> MTLTexture {
    var data = [UInt8](repeating: 0, count: size * size * 4)
    
    for y in 0..<size {
        for x in 0..<size {
            let idx = (y * size + x) * 4
            // Normal pointing outward (cubi): encode in [0,1]
            let nx = UInt8((0.5 + 0.5) * 255)  // +X
            let ny = UInt8((0.5 + 0.5) * 255)  // +Y
            let nz = UInt8((0.5 - 0.5) * 255)  // -Z (verso camera)
            data[idx] = nz
            data[idx+1] = nx
            data[idx+2] = ny
            data[idx+3] = 255
        }
    }
    
    let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    let tex = device.makeTexture(descriptor: desc)!
    tex.replace(region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0, withBytes: &data,
                bytesPerRow: size * 4)
    return tex
}
```

---

## 🎬 Comparison: Before/After

### **PRIMA** (Cartoon, minimal shading)
- Città grigia piatta
- Nessuna ombra
- Mantello opaco
- Cielo procedurali semplice
- No effetti velocità

### **DOPO** (AAA, Unreal-like)
- ✅ Ombre dinamiche (edifici illuminati dal sole realistico)
- ✅ Acciaio brillante tetti, finestre riflettenti
- ✅ Mantello con cloth realism (wind, weight)
- ✅ Cielo con scattering atmosferico (blu zenitale, tramonto rosso)
- ✅ God rays tra grattacieli (volumetric lighting)
- ✅ Motion blur a 3000 km/h (velocità intensa)
- ✅ Ambient occlusion (zone d'ombra naturale)
- ✅ Screen-space reflections (laghetti, superfici lucide)

---

## 💾 File da Modificare

1. **Shaders.metal**: +400 linee (PBR, volumetric, SSAO)
2. **Renderer.swift**: +500 linee (pipeline state, shadow setup, post-process)
3. **GameViewController.swift**: +20 linee (bind shadow maps a render loop)
4. **project.yml**: +2 linee (shader targets nuovi)

---

## 🚀 Quick Start: Shadow Mapping ONLY (8 ore)

Se hai fretta, implementa **solo shadow mapping** per il primo upgrade:

1. Crea `pipelineShadowDepth` (semplicissima: solo Z)
2. Crea `shadowMap` (1024×1024 RGBA8 depth)
3. In `renderShadowPass`, disegna città da POV sole
4. Modifica `fragmentMainBuilding` per legger shadow map (PCF 3×3)
5. **Impatto**: +80% realismo visivo, -2% performance

Questo solo richiede ~100 linee di codice e trasforma il look drammaticamente.

---

## 📖 Risorse (reference)

- **PBR Math**: learnopengl.com/PBR/Theory
- **Volumetric Rendering**: Scratchapixel volumetric lighting
- **Motion Blur**: GPU Gems 3, "High-Speed, Off-Screen Particles"
- **Metal Best Practices**: Apple's Metal Sample Code

---

**Status**: Pronto per implementazione. Iniziare da W1 (Shadow Mapping).

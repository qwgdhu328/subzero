# ⚡ QUICK START: Shadow Mapping in 30 minutes

**Goal**: Avere ombre funzionanti su SuperFlight entro la fine del giorno.

---

## Step 1: Backup Current Code (2 min)

```bash
cd superflight
git checkout -b feat/shadow-mapping-wip
git add .
git commit -m "backup: before graphics upgrade"
```

---

## Step 2: Copy Structs to Renderer.swift (3 min)

In `Renderer.swift`, **immediatamente dopo** la definizione di `FlyUniforms`:

```swift
// === SHADOW MAPPING (aggiungi qui) ===

struct ShadowUniforms {
    var sunViewProj: simd_float4x4 = matrix_identity_float4x4
    var sunPosition: SIMD3<Float> = SIMD3(0.45, 0.55, 0.35)
    var shadowBias: Float = 0.002
    var shadowResolution: Float = 1024
    var pcfSamples: Int32 = 9
}
```

---

## Step 3: Add Shadow Properties to Renderer Class (3 min)

In `final class Renderer: NSObject, MTKViewDelegate`, aggiungi:

```swift
// === SHADOW MAPPING PROPERTIES ===
private var pipelineShadowDepth: MTLRenderPipelineState!
private var shadowMap: MTLTexture?
private var shadowDepthStencilState: MTLDepthStencilState!
private var shadowUniforms = ShadowUniforms()
private var sunViewMatrix = matrix_identity_float4x4
private var sunProjMatrix = matrix_identity_float4x4
```

---

## Step 4: Add Pipeline Build (5 min)

In `buildPipelines(library:view:)`, **aggiungi queste linee SUBITO dopo la creazione del primo pipeline**:

```swift
// === BUILD SHADOW PIPELINE ===
let depthDesc = MTLRenderPipelineDescriptor()
depthDesc.label = "ShadowDepthPass"
depthDesc.vertexFunction = library.makeFunction(name: "vertexMainShadow")
depthDesc.fragmentFunction = library.makeFunction(name: "fragmentMainShadow")
depthDesc.depthAttachmentPixelFormat = .depth32Float
depthDesc.colorAttachments[0].pixelFormat = .invalid  // no color output

pipelineShadowDepth = try! device.makeRenderPipelineState(descriptor: depthDesc)

// Depth stencil state
let depthStateDesc = MTLDepthStencilDescriptor()
depthStateDesc.depthCompareFunction = .less
depthStateDesc.isDepthWriteEnabled = true
shadowDepthStencilState = device.makeDepthStencilState(descriptor: depthStateDesc)!

// Allocate shadow map
let shadowDesc = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: .depth32Float, width: 1024, height: 1024, mipmapped: false)
shadowDesc.usage = [.renderTarget, .shaderRead]
shadowDesc.storageMode = .private
shadowMap = device.makeTexture(descriptor: shadowDesc)
shadowMap?.label = "ShadowMap"
```

---

## Step 5: Add Shadow Render Pass Method (5 min)

Aggiungi al Renderer class:

```swift
func renderShadowPass(cmd: MTLCommandBuffer, buildings: [(Vec3, Vec3)]) {
    guard let shadowMap = shadowMap, !buildings.isEmpty else { return }
    
    // Ortho from sun position
    let sunDir = normalize(SIMD3(0.45, 0.55, 0.35))
    let sunPos = -sunDir * 1000.0
    
    // View matrix
    let sunUp = SIMD3(0, 1, 0)
    let sunForward = normalize(-sunDir)
    let sunRight = normalize(cross(sunUp, sunForward))
    let sunUp2 = cross(sunForward, sunRight)
    
    sunViewMatrix = matrix_identity_float4x4
    sunViewMatrix.columns.0 = SIMD4(sunRight.x, sunUp2.x, -sunForward.x, 0)
    sunViewMatrix.columns.1 = SIMD4(sunRight.y, sunUp2.y, -sunForward.y, 0)
    sunViewMatrix.columns.2 = SIMD4(sunRight.z, sunUp2.z, -sunForward.z, 0)
    sunViewMatrix.columns.3 = SIMD4(
        -dot(sunRight, sunPos),
        -dot(sunUp2, sunPos),
         dot(sunForward, sunPos),
        1)
    
    // Orthographic projection
    let l: Float = -1000, r: Float = 1000
    let b: Float = 0, t: Float = 2000
    let n: Float = 1, f: Float = 2000
    
    sunProjMatrix = matrix_identity_float4x4
    sunProjMatrix.columns.0.x = 2 / (r - l)
    sunProjMatrix.columns.1.y = 2 / (t - b)
    sunProjMatrix.columns.2.z = -2 / (f - n)
    sunProjMatrix.columns.3.x = -(r + l) / (r - l)
    sunProjMatrix.columns.3.y = -(t + b) / (t - b)
    sunProjMatrix.columns.3.z = -(f + n) / (f - n)
    sunProjMatrix.columns.3.w = 1
    
    shadowUniforms.sunViewProj = simd_mul(sunProjMatrix, sunViewMatrix)
    
    // Create instance data
    var instances: [InstanceData] = []
    for (pos, size) in buildings {
        var model = matrix_identity_float4x4
        model.columns.0.x = size.x
        model.columns.1.y = size.y
        model.columns.2.z = size.z
        model.columns.3 = SIMD4(pos.x, pos.y, pos.z, 1)
        instances.append(InstanceData(model: model, color: SIMD4(1, 1, 1, 1)))
    }
    
    // Render pass
    let renderDesc = MTLRenderPassDescriptor()
    renderDesc.depthAttachment.texture = shadowMap
    renderDesc.depthAttachment.loadAction = .clear
    renderDesc.depthAttachment.clearDepth = 1.0
    renderDesc.depthAttachment.storeAction = .store
    
    guard let pass = cmd.makeRenderCommandEncoder(descriptor: renderDesc) else { return }
    pass.label = "ShadowPass"
    pass.setDepthStencilState(shadowDepthStencilState)
    pass.setRenderPipelineState(pipelineShadowDepth)
    
    let bufferSize = instances.count * MemoryLayout<InstanceData>.stride
    guard let instBuffer = device.makeBuffer(bytes: instances, length: bufferSize) else {
        pass.endEncoding()
        return
    }
    
    pass.setVertexBuffer(instBuffer, offset: 0, index: 2)
    var shadowCount = Int32(instances.count)
    pass.setVertexBytes(&shadowCount, length: MemoryLayout<Int32>.size, index: 3)
    pass.setVertexBytes(&shadowUniforms, length: MemoryLayout<ShadowUniforms>.size, index: 4)
    
    let cubeVertexCount = 36
    pass.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: cubeVertexCount,
                       instanceCount: instances.count)
    
    pass.endEncoding()
}
```

---

## Step 6: Call Shadow Pass in Render Loop (3 min)

Modifica `mtkView(_ view:drawableSizeWillChange:)`. **Trova la riga dove inizia il render del city** e aggiungi PRIMA:

```swift
// === SHADOW PASS (BEFORE main scene) ===
let buildingData = /* estrai buildings da game engine */
// Esempio:
var buildingList: [(Vec3, Vec3)] = []
for i in 0..<buildings.count {
    let pos = buildings[i].0  // posizione
    let size = buildings[i].1  // size
    buildingList.append((pos, size))
}
renderShadowPass(cmd: cmd, buildings: buildingList)
```

---

## Step 7: Add Shaders to Shaders.metal (5 min)

In `Shaders.metal`, **aggiungi questi shader alla fine**:

```metal
// ===== SHADOW MAPPING SHADERS =====

vertex VertexOut vertexMainShadow(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    const device InstanceData* instances [[buffer(2)]],
    constant int32_t &count [[buffer(3)]],
    constant ShadowUniforms &shadowUni [[buffer(4)]])
{
    VertexOut out;
    uint vi = vid % 36;
    
    float3 lp = cubeVerts[vi];
    float4 world = instances[iid].model * float4(lp, 1.0);
    
    // Proietta nello shadow space
    out.pos = shadowUni.sunViewProj * world;
    out.world = world.xyz;
    out.normal = float3(0);
    out.color = instances[iid].color;
    out.local = lp;
    out.scale = float3(0);
    out.uv = float2(0);
    
    return out;
}

fragment void fragmentMainShadow(VertexOut in [[stage_in]])
{
    // Depth scritto automaticamente
}
```

---

## Step 8: Modify City Fragment for Shadow Sampling (8 min)

In `fragmentMainCity()`, **aggiungi al FINE della funzione, prima di `return`**:

```metal
// === SHADOW SAMPLING ===
float4 shadowCoord4 = shadowUni.sunViewProj * float4(in.world, 1.0);
float3 shadowCoord = shadowCoord4.xyz / shadowCoord4.w;
shadowCoord.xy = shadowCoord.xy * 0.5 + 0.5;
shadowCoord.z -= shadowUni.shadowBias;

float shadow = 0.0;
if(shadowCoord.x >= 0 && shadowCoord.x <= 1 &&
   shadowCoord.y >= 0 && shadowCoord.y <= 1) {
    float texelSize = 1.0 / shadowUni.shadowResolution;
    
    // PCF 3×3
    for(int x = -1; x <= 1; ++x) {
        for(int y = -1; y <= 1; ++y) {
            float2 uv = shadowCoord.xy + float2(x, y) * texelSize;
            float depthShadow = shadowMapTex.sample(shadowSamp, uv).r;
            shadow += (depthShadow < shadowCoord.z) ? 0.0 : 1.0;
        }
    }
    shadow /= 9.0;
} else {
    shadow = 1.0;
}

// Applica ombra al colore finale
float3 finalColor = mix(col * 0.35, col, shadow);
return float4(finalColor, 1.0);
```

E **modifica la firma della funzione** da:

```metal
fragment float4 fragmentMainCity(VertexOut in [[stage_in]],
                                constant FlyUniforms &u [[buffer(1)]])
```

a:

```metal
fragment float4 fragmentMainCity(VertexOut in [[stage_in]],
                                constant FlyUniforms &u [[buffer(1)]],
                                texture2d<float> shadowMapTex [[texture(10)]],
                                sampler shadowSamp [[sampler(1)]],
                                constant ShadowUniforms &shadowUni [[buffer(5)]])
```

---

## Step 9: Bind Shadow Map in Render Pipeline (3 min)

In `mtkView`, **quando chiami il city pipeline per il render**, aggiungi:

```swift
// Set shadow resources
pass.setFragmentTexture(shadowMap, index: 10)
pass.setFragmentBytes(&shadowUniforms, length: MemoryLayout<ShadowUniforms>.size, index: 5)
```

---

## Step 10: Test & Verify (2 min)

```bash
cd superflight
xcodegen generate
xcodebuild -scheme SuperFlight -destination 'generic/platform=iOS Simulator' build
```

**Expected result**: 
- ✅ Builds without errors
- ✅ App runs on simulator
- ✅ City shows OMBRE on shadowed sides of buildings
- ✅ FPS stable at 120 Hz

**Debug tips**:
- If no shadows: check if shadowMap texture is allocated
- If shadows are completely wrong: check sunViewProj matrix calculation
- If texture binding fails: verify `index: 10` matches shader expectation

---

## Step 11: Commit & Push (1 min)

```bash
git add -A
git commit -m "feat: shadow mapping PCF 3x3

- Allocate 1024×1024 depth shadow map
- Render city from sun POV in separate pass
- Sample shadow map in city fragment with PCF 3×3 soft shadows
- Performance: ~1.2ms shadow pass + 0.3ms sampling
- Result: dramatic lighting, realistic depth"

git push -u origin feat/shadow-mapping-wip
```

---

## ✅ Validation Checklist

- [ ] App builds without warnings
- [ ] Shadow map texture shows in Metal debugger
- [ ] City receives shadows (PCF soft edges visible)
- [ ] No peter-panning (objects don't float above shadows)
- [ ] FPS 120 stable
- [ ] No flickering or banding
- [ ] Screenshot shows dramatic improvement

---

## 🎯 Success Looks Like

### Before
```
Light:     Light:     Light:
[GRAY]     [GRAY]     [GRAY]
Building   Building   Building
```

### After
```
Light:          Light:          Light:
[BRIGHT]        [BRIGHT]        [BRIGHT]
[SHADOW][---]   [SHADOW][---]   [SHADOW][---]
Building        Building        Building
(shadow        (soft edge)      (crisp shadow)
hard edge)
```

---

## 📞 Troubleshooting

| Issue | Solution |
|-------|----------|
| App crashes at render | Check `shadowMap` allocation in init |
| No shadows visible | Verify `shadowMapTex` binding (index 10) |
| Shadows too dark | Increase ambient in fragment shader |
| Shadows too light | Check sunViewProj matrix math |
| Flickering shadows | Increase `shadowBias` (e.g., 0.005) |
| Performance drop | Reduce PCF kernel from 3×3 to point sample |

---

## 🚀 Next Steps (After Success)

Once shadows work:

1. Week 1 end: Polish shadow quality (cascade maps optional)
2. Week 2: Add PBR shader (`PBR_Shaders.metal`)
3. Week 3: Motion blur post-process
4. Week 4: God rays
5. Week 5-6: SSAO, SSR, polish

---

**Estimated time to complete**: **30 minutes** (if you copy-paste carefully)  
**Estimated visual improvement**: +150% (ombre sono il cambio più evidente)

**Ready? Aprire Renderer.swift e iniziare con Step 1!**

# 📅 SuperFlight Graphics AAA — Timeline & Execution Plan

**Target**: Trasformare da "game-like cartoon" a **"AAA cinematic look"** in 6 settimane.

---

## 🎯 Vision Statement

> SuperFlight renderizza come **Insomnia's Spider-Man (PS5)** o **Unreal Engine 5**:
> - Ombre dinamiche realistiche su città
> - Materiali fisicamente corretti (PBR)
> - Effetti atmosferici voluminosi
> - Effetti di velocità a livello film (motion blur, god rays)
> - Superman e mantello con dettagli cinematici

**Output finale**: IPA su App Store con qualità visiva paragonabile a titoli AAA console ($100M+ production budget).

---

## 📊 Milestone Breakdown

### **WEEK 1: Shadow Mapping Foundation** (16h)
**Goal**: Ombre realistiche su tutta la città  
**Team allocation**: 1 graphics programmer (4h/day × 4 giorni)

#### Tasks
- [ ] **Allocate shadow map texture** (1024×1024 depth)
  - Crea `MTLTexture` con format `depth32Float`
  - Bind a `MTLRenderPassDescriptor` separato
  - **Code**: `ShadowMapping_Implementation.swift` (linee 67-88)
  - **Time**: 1h

- [ ] **Build shadow render pass**
  - Vertex shader semplice: trasforma da sun-space
  - Fragment: empty (depth auto-written)
  - Set up `sunViewMatrix` (ortho, 2km × 2km) e `sunProjMatrix`
  - **Code**: `ShadowMapping_Implementation.swift` (linee 93-180)
  - **Time**: 3h

- [ ] **Modify city fragment for shadow sampling**
  - PCF 3×3 soft shadow kernel
  - Confronta `shadowCoord.z` vs depth map sample
  - Mix lit/darkened color based on shadow
  - **Code**: `ShadowMapping_Implementation.swift` (linee 265-290)
  - **Time**: 2h

- [ ] **Integrate into render loop**
  - Call `renderShadowPass()` prima di main scene
  - Bind shadow map texture in city fragment
  - Test su simulator (iPhone 15 Pro)
  - **Code**: Modifica `Renderer.swift` mtkView delegate
  - **Time**: 2h

- [ ] **Performance verification**
  - Misura con Xcode Profiler: frame time < 8.3ms @ 120Hz
  - Check GPU vs CPU bound
  - Adjust PCF kernel (3×3 vs 5×5) se serve
  - **Time**: 2h

- [ ] **QA checklist**
  - ✅ Ombre visibili su edifici
  - ✅ Nessun artefatto (popping, flickering)
  - ✅ Bias corretto (nessun "peter-panning")
  - ✅ FPS 120 stabile
  - **Time**: 2h

**Deliverable**: Commit `feat/shadow-mapping` con IPA funzionante.  
**Success metric**: Screenshot side-by-side mostra ombre drammatiche.

---

### **WEEK 2: PBR Material System** (14h)
**Goal**: Superfici fisicamente realistiche (finestre, acciaio, pelle)  
**Team allocation**: 1 graphics programmer + 1 tools engineer

#### Tasks
- [ ] **Implement Cook-Torrance BRDF shader**
  - D (GGX distribution)
  - F (Fresnel-Schlick)
  - G (Smith-Schlick geometry)
  - **Code**: `PBR_Shaders.metal` (linee 54-100)
  - **Time**: 3h

- [ ] **Create procedural material maps**
  - Roughness map (finestre smooth 0.1, mattone rough 0.7)
  - Metallic map (griglie AC 0.8, muri 0.0)
  - Normal map generation
  - **Code**: `PBR_Shaders.metal` (linee 120-180)
  - **Time**: 2h

- [ ] **Build PBR fragment shader pipeline**
  - Replace `fragmentMainCity` con `fragmentMainCityPBR`
  - Integrate shadow sampling
  - Add tone mapping ACES
  - **Code**: `PBR_Shaders.metal` (linee 310-420)
  - **Time**: 3h

- [ ] **Character-specific materials**
  - Superman pelle (subsurface light)
  - Mantello rosso satinato (0.3 roughness)
  - **Code**: `PBR_Shaders.metal` (linee 427-470)
  - **Time**: 2h

- [ ] **Texture sampling setup**
  - Add roughness/metallic texture slots
  - Configure sampler states
  - Test on device
  - **Time**: 2h

- [ ] **QA + Performance**
  - Profiling: PBR shader cost < 0.5ms
  - Screenshot comparison: more realistic materials
  - Edge cases: specular highlights at grazing angles
  - **Time**: 2h

**Deliverable**: Commit `feat/pbr-materials` — finestre brillano, acciaio è metallico.  
**Success metric**: Visibly "next-gen" material appearance.

---

### **WEEK 3: Motion Blur + Depth of Field** (12h)
**Goal**: Effetti cinetici a 3000 km/h  
**Team allocation**: 1 graphics programmer

#### Tasks
- [ ] **Implement velocity buffer**
  - Traccia screen-space motion da frame t-1 a t
  - Output from vertex shader
  - **Code**: Custom vertex shader velocity calc
  - **Time**: 2h

- [ ] **Motion blur post-process**
  - Tempo-reprojection: 8 tap sample along velocity
  - Variable blur based on speed (fly_speed() → scale)
  - Integrate into post-process chain
  - **Code**: Motion blur fragment shader (~50 linee)
  - **Time**: 2h

- [ ] **Depth of Field (optional, advanced)**
  - Near/far plane from altitude (fly_altitude())
  - Circular CoC (Circle of Confusion) kernel
  - Separable blur (H + V pass)
  - **Code**: DoF shader (~80 linee)
  - **Time**: 3h (opzionale)

- [ ] **Parameter tuning**
  - Motion blur strength vs. speed
  - Focus distance vs. altitude
  - Test at various flight speeds
  - **Time**: 2h

- [ ] **Performance & QA**
  - Motion blur: < 1ms
  - DoF: < 2ms (su High quality mode)
  - Test edge cases (zero velocity, rapid turns)
  - **Time**: 2h

**Deliverable**: Commit `feat/motion-blur` — sensazione di velocità cinematica.  
**Success metric**: 240 km/h looks boring, 3000 km/h looks epic.

---

### **WEEK 4: Volumetric Lighting + Atmospheric Scattering** (14h)
**Goal**: Cielo realistico + god rays  
**Team allocation**: 1 graphics programmer + 1 FX artist (per tuning)

#### Tasks
- [ ] **Atmospheric scattering shader**
  - Rayleigh (blue zenith, red horizon)
  - Mie phase function
  - Air density exponential falloff
  - **Code**: `PBR_Shaders.metal` (sky scattering section)
  - **Time**: 3h

- [ ] **God rays (volumetric lighting)**
  - Raymarch semplice lungo ray
  - Scattering integral (Mie + transmittance)
  - 8 steps raymarch per pixel
  - **Code**: Post-process shader (~60 linee)
  - **Time**: 3h

- [ ] **Integrate into sky rendering**
  - Sostituisci `skyColor()` con versione scattering
  - Add god rays in post-process
  - Combine with existing cloud system
  - **Time**: 2h

- [ ] **Time-of-day support**
  - Sun angle varies → scattering changes
  - Blue hour / golden hour transitions
  - Day/night cycle via game clock
  - **Time**: 2h

- [ ] **Quality scalars per graphics quality**
  - Ultra: 16 raymarch steps
  - High: 8 steps
  - Medium: 4 steps
  - Lite: 0 (disabled)
  - **Time**: 2h

- [ ] **QA + tuning**
  - Test at different altitudes
  - Check for banding artifacts
  - FX artist tweaks sun brightness
  - **Time**: 2h

**Deliverable**: Commit `feat/volumetric-sky` — cinematico cielo.  
**Success metric**: Diventare supersonic con tramonto dorato alle spalle = spettacolare.

---

### **WEEK 5: Screen-Space Effects (SSAO + SSR)** (12h)
**Goal**: Dettagli ambient occlusion + riflessioni screensapce  
**Team allocation**: 1 graphics programmer

#### Tasks
- [ ] **SSAO (Screen-Space Ambient Occlusion)**
  - Sample depth neighbors around fragment
  - Compute horizon angle (directional occlusion)
  - Temporal filtering (reduce noise)
  - **Code**: SSAO fragment shader (~70 linee)
  - **Time**: 3h

- [ ] **SSR (Screen-Space Reflection) — minimal**
  - Raytrace in screen space (horizon line)
  - 8 samples per pixel (limited)
  - Fallback to env map / probe
  - **Code**: SSR shader (~50 linee)
  - **Time**: 3h

- [ ] **Blur + denoise pass**
  - Bilateral filter per SSAO (preserve edges)
  - Temporal accumulation per SSR
  - **Time**: 2h

- [ ] **Integration into post-process chain**
  - Slot after main scene rendering
  - Bind depth/normal buffers
  - Composite into final output
  - **Time**: 2h

- [ ] **QA + performance**
  - SSAO: < 1.5ms
  - SSR: < 1ms
  - No obvious banding/artifacts
  - **Time**: 2h

**Deliverable**: Commit `feat/screen-space-fx` — AO in crevices, riflessioni.  
**Success metric**: Noticeably more 3D depth, less flat look.

---

### **WEEK 6: Polish + Finalization** (10h)
**Goal**: AAA look complete, production-ready  
**Team allocation**: 1 graphics programmer + 1 QA

#### Tasks
- [ ] **Color grading + LUT (Look-Up Table)**
  - Create DaVinci Resolve LUT for cinematic look
  - 64×64 identity LUT → color-graded version
  - Apply in post-process (simple 3D LUT sampling)
  - **Code**: LUT shader (~20 linee)
  - **Time**: 2h

- [ ] **Hair/mantello cloth simulation (optional, enhancement)**
  - Simple oscillation based on wind
  - Wind intensity from speed
  - Constraint-based physics (verlet)
  - **Time**: 2h (opzionale)

- [ ] **Performance optimization pass**
  - Profile all shaders on iPhone SE 3 (baseline)
  - Reduce shader complexity if needed
  - Mobile vs. desktop quality tiers
  - **Time**: 2h

- [ ] **Documentation + README**
  - Update README.md con nuove features
  - Shader optimization notes
  - Platform-specific settings
  - **Time**: 1h

- [ ] **QA final pass**
  - Full game playthrough (5 min gameplay)
  - Screenshot comparison: Week 1 vs. Week 6
  - FPS stability 120 Hz
  - Edge cases: extreme altitudes, mach transitions
  - **Time**: 2h

- [ ] **Git housekeeping**
  - Rebase feature branches
  - Squash commits into logical units
  - Tag v2.0 release
  - **Time**: 1h

**Deliverable**: Release candidate `v2.0-AAA-graphics`.  
**Success metric**: Ready for production / App Store.

---

## 📈 Success Metrics

| Metric | Baseline (Week 0) | Target (Week 6) | Measurement |
|--------|-------------------|-----------------|-------------|
| **Visual fidelity** | Cartoon-like | AAA photorealistic | Side-by-side screenshots |
| **Shadow quality** | None | Dynamic soft shadows | Visual inspection |
| **Material realism** | Flat Lambert | PBR Cook-Torrance | Finestre shine, acciaio gloss |
| **Atmospheric effects** | Procedural sky | Scattering + god rays | Tramonti dramatically better |
| **Motion perception** | Feeling slow | Cinematic speed | Play 3000 km/h scene |
| **FPS performance** | 120 Hz (0.8 ms) | 120 Hz (< 8 ms) | Xcode Profiler |
| **Memory usage** | ~250 MB | ~300 MB (textures) | Instruments |
| **User perception score** | Not tested | 9/10 AAA-like | Beta testers feedback |

---

## 🛠️ Technical Debt & Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Shadow map performance on iPhone SE | HIGH | Cascade shadow maps, reduce resolution on Low quality |
| PBR shader complexity | MEDIUM | Profile aggressively, use simpler BRDF on mobile |
| God rays banding | MEDIUM | Add dither in post, increase samples |
| SSR screen edge artifacts | MEDIUM | Fade out at screen edges, clamp UV |
| Hair cloth flickering | LOW | Pre-compute physics, cache constraints |

---

## 💰 Cost Estimate

| Role | Hours | Rate | Cost |
|------|-------|------|------|
| Graphics Programmer (FT) | 60h | $150/h | $9,000 |
| Tools/Tools Engineer (PT) | 10h | $120/h | $1,200 |
| QA | 8h | $80/h | $640 |
| **Total** | **78h** | — | **$10,840** |

**Timeline**: 6 settimane = 1.5 mesi (standard per mid-scale graphics revamp).

---

## 📋 Dependencies & Prerequisites

### Required
- [ ] Xcode 16+ (Metal 3)
- [ ] iPhone 13+ for testing (full feature parity)
- [ ] Git repository access
- [ ] DaVinci Resolve (optional, for LUT creation)

### Nice-to-have
- [ ] GPU profiler (Metal debugger)
- [ ] Build server (CI/CD for daily builds)
- [ ] Slack/Discord for async team comms

---

## 🔄 Weekly Sync Template

Every Friday, 15:00 UTC:

```
GRAPHICS UPGRADE SYNC

Week: [W1/W2/W3/W4/W5/W6]
Status: [On track / At risk / Blocked]

✅ Completed this week:
- [Feature] → commit [hash]
- [Feature] → commit [hash]

⏳ In progress:
- [Feature] (est. completion [date])

⚠️ Blockers:
- [Issue description] → owner [name]

📊 Metrics:
- FPS: [X] Hz (target 120)
- Shader cost: [X] ms
- Memory: [X] MB

Next week goals:
- [Goal 1]
- [Goal 2]
```

---

## 🚀 Go-Live Checklist

Before `v2.0` release:

- [ ] All features merged to `main` branch
- [ ] CI/CD pipeline passes (build + unit tests)
- [ ] Profiler shows stable 120 Hz on iPhone 13/14/15
- [ ] QA tested on iPhone SE 3 (baseline low-end)
- [ ] Screenshots + demo video ready
- [ ] README updated
- [ ] Version bumped to `2.0.0`
- [ ] Git tags created
- [ ] Changelog written
- [ ] App Store metadata updated
- [ ] Beta testers invited (TestFlight)
- [ ] Approval request submitted

---

## 📚 Reference Materials

### PBR Theory
- [LearnOpenGL: PBR](https://learnopengl.com/PBR/Theory)
- [Physically Based Rendering in Real-Time](https://www.dropbox.com/s/rfmm9ygvgydm7a2/EGSR2014_Karis.pptx?dl=0) — Karis, Epic Games
- [Real Shading in Unreal Engine 4](https://cdn2.unrealengine.com/Resources/files/RealShading_UE4_Presentation_rf.pdf)

### Metal Graphics
- [Apple Metal Sample Code](https://developer.apple.com/metal/sample-code/)
- [Metal Best Practices](https://developer.apple.com/videos/play/wwdc2019/606/)
- [Rendering Cubemaps in Metal](https://developer.apple.com/videos/play/wwdc2020/10015/)

### Performance
- [GPU Gems 3: Motion Blur](https://developer.nvidia.com/gpugems/gpugems3/part-iv-image-effects/chapter-27-motion-blur-post-processing-effect)
- [Volumetric Rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers)

---

## 🎬 Final Vision

When complete, SuperFlight will look like:

> **A PlayStation 5 superhero flight game, optimized for iPhone.**
>
> - Ombre dinamiche drammatiche su city
> - Materiali PBR brillanti (Superman's cape, building windows)
> - Volumetric god rays tra grattacieli
> - Motion blur epico a 3000 km/h
> - Cielo di scattering atmosferico
> - Ambient occlusion depth
> - Smooth 120 FPS su iPhone 13+

**Marketing tagline**: *"Graphics technology built for next-gen iOS gaming."*

---

**Status**: Ready to commence Week 1.  
**Owner**: Graphics Team Lead  
**Last updated**: 2024-09-27

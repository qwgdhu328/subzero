// Renderer.swift — rendering 3D Metal 4K/HDR: Superman con mesh articolate,
// mantello animato, NPC pedoni, città con strade/nuvole/cielo, raggi oculari,
// cielo procedurale con sole e stelle, post-process bloom + tonemap ACES.

import MetalKit
import simd

// Layout identico al FlyUniforms di Shaders.metal: solo float4x4 e float4
// (float3 ha allineamento 16 in Metal e divergerebbe da SIMD3 in Swift).
struct FlyUniforms {
    var viewProj: simd_float4x4
    var invViewProj: simd_float4x4
    var cameraPosTime: SIMD4<Float>   // xyz = posizione camera, w = tempo
    var fwdAspect: SIMD4<Float>       // xyz = direzione vista, w = aspect
    var sunPre: SIMD4<Float>          // xyz = direzione sole, w = scala prepass
    var bufferSizePad: SIMD4<Float>   // xy = dimensioni buffer

    var time: Float { cameraPosTime.w }
}

struct InstanceData {
    var model: simd_float4x4
    var color: SIMD4<Float>
}

// Layout identico a ShadowUniforms di Shaders.metal: solo float4x4 e float4.
struct ShadowUniforms {
    var sunViewProj: simd_float4x4
    var sunPosRadius: SIMD4<Float>   // xyz = posizione sole, w = raggio area
    var biasResolution: SIMD4<Float> // x = bias depth, y = risoluzione shadow map
}

final class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineCity: MTLRenderPipelineState!    // cubi istanziati (edifici/terra)
    var pipelineMesh: MTLRenderPipelineState!    // mesh personaggi
    var pipelineCape: MTLRenderPipelineState!    // mantello animato
    var pipelineCloud: MTLRenderPipelineState!   // nuvole
    var pipelineGlow: MTLRenderPipelineState!    // anelli/laser/particelle
    var pipelineSky: MTLRenderPipelineState!     // cielo procedurale (0 depth, write mask)
    var pipelineBright: MTLRenderPipelineState!  // post: estrazione HDR
    var pipelineBlurH: MTLRenderPipelineState!   // post: blur orizzontale
    var pipelineBlurV: MTLRenderPipelineState!   // post: blur verticale
    var pipelineComposite: MTLRenderPipelineState! // post: tonemap finale
    var depthState: MTLDepthStencilState!
    var noDepthState: MTLDepthStencilState!
    var skyDepthState: MTLDepthStencilState!     // test always, scrittura disattivata

    // Shadow mapping (W1 del piano AAA): depth-only dal punto di vista del sole.
    var pipelineShadowDepth: MTLRenderPipelineState!
    var shadowDepthState: MTLDepthStencilState!  // scrittura depth senza colore
    var shadowMap: MTLTexture?
    var shadowUniformsBuffer: MTLBuffer?
    var shadowUniforms = ShadowUniforms(
        sunViewProj: matrix_identity_float4x4,
        sunPosRadius: SIMD4<Float>(0, 1000, 0, 1200),
        biasResolution: SIMD4<Float>(0.0015, 2048, 0, 0))
    // W2: pipeline PBR Cook-Torrance, attiva solo se gli shader PBR compilano
    // (makeDefaultLibrary() include vertexMainPBR/fragmentMainCityPBR).
    var pipelineCityPBR: MTLRenderPipelineState?

    var bestScore = 0

    // Target offscreen HDR (scene MSAA + resolve + ping-pong bloom) e depth MSAA.
    private var sceneTex: MTLTexture?
    private var sceneResolveTex: MTLTexture?
    private var bloomA: MTLTexture?
    private var bloomB: MTLTexture?
    private var depthTex: MTLTexture?
    private var texW = 0
    private var texH = 0
    private var prepassScale: Float = 1

    // Buffer istanze
    private var solidInstances: MTLBuffer?
    private var glowInstances: MTLBuffer?
    private var solidCapacity = 1024
    private var glowCapacity = 256
    private var cloudInstances: [InstanceData] = []
    private var cloudBuffer: MTLBuffer?

    // Mesh generate a runtime
    private var sphereVB: MTLBuffer!; private var sphereIB: MTLBuffer!; private var sphereICount = 0
    private var capsuleVB: MTLBuffer!; private var capsuleIB: MTLBuffer!; private var capsuleICount = 0
    private var capeVB: MTLBuffer!
    private static let capeQuadCount = 12   // 4 file × 3 colonne di quad
    private var capeIndices: [UInt16] = []

    private var uniforms = FlyUniforms(
        viewProj: matrix_identity_float4x4, invViewProj: matrix_identity_float4x4,
        cameraPosTime: SIMD4(0, 0, 0, 0),
        fwdAspect: SIMD4(0, 0, -1, 1),
        sunPre: SIMD4(0.45, 0.55, 0.35, 1),
        bufferSizePad: SIMD4(1, 1, 0, 0))

    init(metalKitView: MTKView) {
        device = metalKitView.device!
        commandQueue = device.makeCommandQueue()!
        attachedView = metalKitView
        super.init()
        let lib = device.makeDefaultLibrary()
        buildPipelines(library: lib, view: metalKitView)
        solidInstances = device.makeBuffer(
            length: solidCapacity * MemoryLayout<InstanceData>.stride,
            options: .storageModeShared)
        glowInstances = device.makeBuffer(
            length: glowCapacity * MemoryLayout<InstanceData>.stride,
            options: .storageModeShared)
        buildMeshes()
        buildClouds()
    }

    // Chiamato da GameViewController quando cambia la qualità nelle impostazioni.
    func applyQuality() {
        prepassScale = Float(GameSettings.shared.quality.renderScale)
        texW = 0; texH = 0   // forza realloc dei target al prossimo frame
        // Uscendo da Ultra libera i target offscreen (decine di MB di VRAM).
        if GameSettings.shared.quality != .ultra {
            sceneTex = nil; sceneResolveTex = nil
            bloomA = nil; bloomB = nil; depthTex = nil
        }
        // Ultra ha formati diversi (HDR + MSAA 4x): le pipeline vanno ricostruite.
        if let view = attachedView {
            buildPipelines(library: device.makeDefaultLibrary(), view: view)
        }
        buildMeshes()
    }

    // ------------------------------------------------------------ //
    //  Pipeline

    private func buildPipelines(library: MTLLibrary?, view: MTKView) {
        guard let lib = library else {
            fatalError("Metal library non trovata: controlla Shaders.metal nel target")
        }
        let vsCube = lib.makeFunction(name: "vertexMain")!
        let vsMesh = lib.makeFunction(name: "meshVertex")!
        let vsCape = lib.makeFunction(name: "capeVertex")!
        let fsCity = lib.makeFunction(name: "fragmentMain")!
        let fsFab  = lib.makeFunction(name: "fabricFragment")!
        let fsCloud = lib.makeFunction(name: "cloudFragment")!
        let fsGlow = lib.makeFunction(name: "glowFragment")!
        let fsSky  = lib.makeFunction(name: "skyFragment")!
        let vsPost = lib.makeFunction(name: "postVertex")!
        let fsBright = lib.makeFunction(name: "brightPassFrag")!
        let fsBlur = lib.makeFunction(name: "blurFrag")!
        let fsComp = lib.makeFunction(name: "compositeFrag")!

        // Pixel format in base alla qualità: Ultra usa HDR (RGBA16Float) + MSAA 4x.
        let ultra = GameSettings.shared.quality == .ultra
        let colorFmt: MTLPixelFormat = ultra ? .rgba16Float : view.colorPixelFormat
        let depthFmt: MTLPixelFormat = ultra ? .depth32Float : view.depthStencilPixelFormat
        let sampleCount = ultra ? 4 : 1

        func makePipe(_ vs: MTLFunction, _ fs: MTLFunction,
                      additive: Bool, depthFormat: MTLPixelFormat,
                      blend: Bool = true, writeMask: MTLColorWriteMask = [.red, .green, .blue, .alpha],
                      colorFormat: MTLPixelFormat? = nil, samples: Int = 0) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vs
            d.fragmentFunction = fs
            d.colorAttachments[0].pixelFormat = colorFormat ?? colorFmt
            d.colorAttachments[0].isBlendingEnabled = blend
            d.colorAttachments[0].rgbBlendOperation = .add
            d.colorAttachments[0].alphaBlendOperation = .add
            if additive {
                d.colorAttachments[0].sourceRGBBlendFactor = .one
                d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            } else {
                d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
                d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            }
            d.colorAttachments[0].sourceAlphaBlendFactor = .one
            d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            d.colorAttachments[0].writeMask = writeMask
            d.depthAttachmentPixelFormat = depthFormat
            d.rasterSampleCount = samples > 0 ? samples : sampleCount
            return (try? device.makeRenderPipelineState(descriptor: d))!
        }

        pipelineCity = makePipe(vsCube, fsCity, additive: false, depthFormat: depthFmt)
        pipelineMesh = makePipe(vsMesh, fsFab, additive: false, depthFormat: depthFmt)
        pipelineCape = makePipe(vsCape, fsFab, additive: false, depthFormat: depthFmt)
        pipelineCloud = makePipe(vsCube, fsCloud, additive: false, depthFormat: depthFmt)
        pipelineGlow = makePipe(vsCube, fsGlow, additive: true, depthFormat: depthFmt)
        // Cielo: depth always + write mask RGB (alpha resta 1.0 per i pass successivi).
        let dsdSky = MTLDepthStencilDescriptor()
        dsdSky.depthCompareFunction = .always
        dsdSky.isDepthWriteEnabled = false
        skyDepthState = device.makeDepthStencilState(descriptor: dsdSky)!
        pipelineSky = makePipe(vsPost, fsSky, additive: false, depthFormat: depthFmt,
                               blend: false, writeMask: [.red, .green, .blue])
        // Post-process: niente depth, niente blend (sovrascrittura piena).
        // Bright/blur scrivono sulle texture bloom HDR; il composite scrive sul
        // drawable (LDR anche in Ultra). Nessuno usa MSAA.
        let postDepth = MTLPixelFormat.invalid
        let bloomFmt: MTLPixelFormat = ultra ? .rgba16Float : colorFmt
        let drawableFmt: MTLPixelFormat = view.colorPixelFormat
        pipelineBright = makePipe(vsPost, fsBright, additive: false,
                                  depthFormat: postDepth, blend: false,
                                  colorFormat: bloomFmt, samples: 1)
        pipelineBlurH = makePipe(vsPost, fsBlur, additive: false,
                                 depthFormat: postDepth, blend: false,
                                 colorFormat: bloomFmt, samples: 1)
        pipelineBlurV = makePipe(vsPost, fsBlur, additive: false,
                                 depthFormat: postDepth, blend: false,
                                 colorFormat: bloomFmt, samples: 1)
        pipelineComposite = makePipe(vsPost, fsComp, additive: false,
                                     depthFormat: postDepth, blend: false,
                                     colorFormat: drawableFmt, samples: 1)

        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsd)!
        let dsd2 = MTLDepthStencilDescriptor()
        dsd2.depthCompareFunction = .less
        dsd2.isDepthWriteEnabled = false
        noDepthState = device.makeDepthStencilState(descriptor: dsd2)!

        // ---- Shadow mapping (W1) + PBR città (W2) del piano AAA ----
        // La shadow map copre l'intera città: bias e risoluzione uniformi per
        // il PCF 3×3 nel fragment della città.
        // Ultra 4K: shadow map 2048²; qualità inferiori: 1024² (meno VRAM).
        let shadowRes: Int = GameSettings.shared.quality == .ultra ? 2048 : 1024
        let sTexDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: shadowRes, height: shadowRes, mipmapped: false)
        sTexDesc.usage = [.renderTarget, .shaderRead]
        sTexDesc.storageMode = .private
        shadowMap = device.makeTexture(descriptor: sTexDesc)
        shadowUniforms.biasResolution = SIMD4<Float>(0.0015, Float(shadowRes), 0, 0)
        if shadowUniformsBuffer == nil {
            shadowUniformsBuffer = device.makeBuffer(
                length: MemoryLayout<ShadowUniforms>.stride, options: .storageModeShared)
        }

        let vsShadow = lib.makeFunction(name: "vertexShadowDepth")!
        let shadowDesc = MTLRenderPipelineDescriptor()
        shadowDesc.vertexFunction = vsShadow
        shadowDesc.colorAttachments[0].pixelFormat = .invalid
        shadowDesc.depthAttachmentPixelFormat = .depth32Float
        pipelineShadowDepth = (try? device.makeRenderPipelineState(descriptor: shadowDesc))!

        let dsdSh = MTLDepthStencilDescriptor()
        dsdSh.depthCompareFunction = .less
        dsdSh.isDepthWriteEnabled = true
        shadowDepthState = device.makeDepthStencilState(descriptor: dsdSh)!

        // PBR città: opzionale (W2). Se gli entry point non sono nella libreria
        // si resta su fragmentMain (Lambert + ombre), sempre disponibile.
        if let vsPBR = lib.makeFunction(name: "vertexMainPBR"),
           let fsPBR = lib.makeFunction(name: "fragmentMainCityPBR") {
            pipelineCityPBR = makePipe(vsPBR, fsPBR, additive: false, depthFormat: depthFmt)
        } else {
            pipelineCityPBR = nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        fly_update(1.0 / Double(view.preferredFramesPerSecond),
                   Int32(view.drawableSize.width),
                   Int32(view.drawableSize.height))
        bestScore = max(bestScore, Int(fly_best()))

        guard let drawable = view.currentDrawable,
              let cmd = commandQueue.makeCommandBuffer() else { return }

        let dw = Int(view.drawableSize.width)
        let dh = Int(view.drawableSize.height)
        guard dw > 0, dh > 0 else { return }

        let aspect = Float(dw) / Float(max(1, dh))
        uniforms = makeUniforms(aspect: aspect, width: Float(dw), height: Float(dh))
        shadowUniforms = makeShadowUniforms(time: uniforms.time)

        // Cielo in base alla qualità e alla quota: sopra ~2600 m vira al blu spazio.
        let alt = fly_altitude()
        let spaceT: Float = min(1.0, max(0.0, (alt - 400.0) / 2200.0))
        var skyR: Float = 0.36, skyG: Float = 0.52, skyB: Float = 0.88
        switch GameSettings.shared.quality {
        case .ultra, .media: skyR = 0.42; skyG = 0.60; skyB = 0.90
        case .lite:  skyR = 0.55; skyG = 0.68; skyB = 0.92
        case .alta:  break
        }
        // verso lo spazio: scurisce e vira al blu profondo
        let r: Float = skyR * (1 - spaceT * 0.85)
        let g: Float = skyG * (1 - spaceT * 0.72)
        let b: Float = skyB * (1 - spaceT * 0.45) + 0.03 * spaceT
        let clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: 1)

        // -------- Render pass: cielo + scena (offscreen HDR in Ultra, drawable altrove) --------
        let rpd: MTLRenderPassDescriptor
        if GameSettings.shared.quality == .ultra {
            ensureTargets(width: dw, height: dh)
            guard let sceneTex = sceneTex, let depthTex = depthTex else { return }
            rpd = offscreenPass(scene: sceneTex, depth: depthTex, clear: clearColor)
        } else {
            guard let d = view.currentRenderPassDescriptor else { return }
            d.colorAttachments[0].clearColor = clearColor
            rpd = d
        }
        // -------- Pass 0: shadow mapping (W1 piano AAA) --------
        // Depth-only dal punto di vista del sole, PRIMA di aprire l'encoder
        // della scena (Metal non consente encoder sovrapposti).
        if let sm = shadowMap, let shBuf = shadowUniformsBuffer {
            shBuf.contents().copyMemory(from: &shadowUniforms,
                                        byteCount: MemoryLayout<ShadowUniforms>.stride)
            let shPass = MTLRenderPassDescriptor()
            shPass.depthAttachment.texture = sm
            shPass.depthAttachment.loadAction = .clear
            shPass.depthAttachment.storeAction = .store
            shPass.depthAttachment.clearDepth = 1.0
            if let shEnc = cmd.makeRenderCommandEncoder(descriptor: shPass) {
                shEnc.setCullMode(.none)
                shEnc.setRenderPipelineState(pipelineShadowDepth)
                shEnc.setDepthStencilState(shadowDepthState)
                shEnc.setVertexBuffer(shBuf, offset: 0, index: 1)
                if let city = drawCityMatrices() {
                    var cCount = city.count
                    shEnc.setVertexBuffer(city.buffer, offset: 0, index: 2)
                    shEnc.setVertexBytes(&cCount, length: MemoryLayout<Int32>.stride, index: 3)
                    shEnc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                                         instanceCount: Int(city.count))
                }
                drawGroundShadow(enc: shEnc)
                shEnc.endEncoding()
            }
        }

        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setVertexBuffer(uniformBuffer(), offset: 0, index: 1)
        enc.setFragmentBuffer(uniformBuffer(), offset: 0, index: 1)   // nebbia/luce solare nei fragment
        if let shBuf = shadowUniformsBuffer {
            enc.setFragmentBuffer(shBuf, offset: 0, index: 5)          // uniform ombre
        }
        if let sm = shadowMap {
            enc.setFragmentTexture(sm, index: 10)                      // shadow map (PCF 3×3)
        }
        enc.setFragmentSamplerState(shadowSamplerState, index: 1)
        enc.setCullMode(.none)

        // Cielo procedurale: quad full-screen a depth always, sotto ogni cosa.
        enc.setRenderPipelineState(pipelineSky)
        enc.setDepthStencilState(skyDepthState)
        enc.setFragmentBuffer(uniformBuffer(), offset: 0, index: 1)
        drawFullscreen(enc: enc, pipeline: pipelineSky)

        enc.setDepthStencilState(depthState)

        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        drawGround(enc: enc)
        drawCity(enc: enc)
        drawClouds(enc: enc)
        drawHero(enc: enc)
        drawNpcs(enc: enc)
        drawDebris(enc: enc)
        drawRings(enc: enc)
        drawLaser(enc: enc)
        drawParticles(enc: enc)
        drawSonicBoom(enc: enc)

        enc.endEncoding()

        // -------- Pass 2: post-process (solo Ultra) --------
        if GameSettings.shared.quality == .ultra {
            guard let sceneTex = sceneTex, let bloomATex = bloomA, let bloomBTex = bloomB else { return }

            // Bright pass: scena risolta → bloomA (metà risoluzione).
            let sceneReadable = sceneResolveTex ?? sceneTex
            if let enc = cmd.makeRenderCommandEncoder(descriptor: simplePass(target: bloomATex)) {
                enc.setRenderPipelineState(pipelineBright)
                enc.setFragmentTexture(sceneReadable, index: 0)
                drawFullscreen(enc: enc, pipeline: pipelineBright)
                enc.endEncoding()
            }

            // Blur separabile H+V: bloomA → bloomB → bloomA (ping-pong).
            if let enc = cmd.makeRenderCommandEncoder(descriptor: simplePass(target: bloomBTex)) {
                enc.setRenderPipelineState(pipelineBlurH)
                enc.setFragmentTexture(bloomATex, index: 0)
                var dir = SIMD2<Float>(1, 0)   // offset in texel della texture sorgente
                enc.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Float>>.stride, index: 4)
                drawFullscreen(enc: enc, pipeline: pipelineBlurH)
                enc.endEncoding()
            }
            if let enc = cmd.makeRenderCommandEncoder(descriptor: simplePass(target: bloomATex)) {
                enc.setRenderPipelineState(pipelineBlurV)
                enc.setFragmentTexture(bloomBTex, index: 0)
                var dir = SIMD2<Float>(0, 1)
                enc.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Float>>.stride, index: 4)
                drawFullscreen(enc: enc, pipeline: pipelineBlurV)
                enc.endEncoding()
            }

            // Composite: scena risolta + bloom → tonemap ACES → drawable finale.
            // Il pipeline composite non ha attachment di depth: rimuovilo dal
            // render pass del drawable, altrimenti la validazione Metal fallisce.
            guard let rpd = view.currentRenderPassDescriptor else { return }
            rpd.depthAttachment.texture = nil
            rpd.depthAttachment.loadAction = .dontCare
            if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
                enc.setRenderPipelineState(pipelineComposite)
                enc.setFragmentTexture(sceneResolveTex ?? sceneTex, index: 0)
                enc.setFragmentTexture(bloomATex, index: 1)
                enc.setFragmentBytes(&uniforms, length: MemoryLayout<FlyUniforms>.stride, index: 1)
                drawFullscreen(enc: enc, pipeline: pipelineComposite)
                enc.endEncoding()
            }
        }

        cmd.present(drawable)
        cmd.commit()
    }

    // ------------------------------------------------------------ //
    //  Shadow mapping (W1 del piano AAA)

    /// Sampler per il PCF 3×3 della shadow map.
    private lazy var shadowSamplerState: MTLSamplerState = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .notMipmapped
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        d.compareFunction = nil          // PCF manuale: comparazione nel fragment
        return device.makeSamplerState(descriptor: d)!
    }()

    /// Matrici mondo degli edifici (distrutti esclusi): condivise tra shadow
    /// pass e render pass in un buffer riempito una volta per frame.
    private var cityMatrixBuffer: MTLBuffer?
    private var cityMatrixCapacity = 0
    private var cityMatrixCount: Int32 = 0

    private func drawCityMatrices() -> (buffer: MTLBuffer, count: Int32)? {
        let n = Int(fly_building_count())
        guard n > 0 else { return nil }
        if cityMatrixBuffer == nil || cityMatrixCapacity < n {
            cityMatrixCapacity = max(64, n * 2)
            cityMatrixBuffer = device.makeBuffer(
                length: cityMatrixCapacity * MemoryLayout<InstanceData>.stride,
                options: .storageModeShared)
        }
        guard let buf = cityMatrixBuffer else { return nil }
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: cityMatrixCapacity)
        var count: Int32 = 0
        for i in 0..<n {
            var pos = FlyVec3(); var size = FlyVec3(); var hue: Float = 0
            fly_building(Int32(i), &pos, &size, &hue)
            if size.y <= 0 { continue }        // distrutto dal laser
            let m = MathUtil.translate(x: pos.x, y: pos.y + size.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size.x, sy: size.y, sz: size.z)
            ptr[Int(count)] = InstanceData(model: m, color: SIMD4<Float>(1, 1, 1, 1))
            count += 1
        }
        guard count > 0 else { return nil }
        cityMatrixCount = count
        return (buf, count)
    }

    /// Terra nella shadow map: anche il suolo riceve ombre dagli edifici, quindi
    /// deve scriverle (bias del fragment evita l'auto-ombreggiatura falsa).
    private func drawGroundShadow(enc: MTLRenderCommandEncoder) {
        let m = MathUtil.translate(x: 0, y: -1.0, z: 0)
            * MathUtil.scaleNonUniform(sx: 1600, sy: 1.0, sz: 2600)
        var inst = InstanceData(model: m, color: SIMD4<Float>(1, 1, 1, 1))
        enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
        var one = Int32(1)
        enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: 1)
    }

    /// Vista-proiezione ortografica del sole: centro l'area sulla città e la
    /// oriento dal sole verso l'origine (approccio QUICK_START, adattato a
    /// MathUtil del progetto).
    private func makeShadowUniforms(time: Float) -> ShadowUniforms {
        let sun = MathUtil.sunDirection(time: time)
        let dist: Float = 1400.0
        let sunPos = SIMD3<Float>(sun.x * dist, sun.y * dist + 250, sun.z * dist)
        let target = SIMD3<Float>(0, 200, 0)   // centro area città
        let fwd = simd_normalize(target - sunPos)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(fwd, worldUp))
        let up = simd_normalize(simd_cross(right, fwd))

        var V = matrix_identity_float4x4
        V.columns.0 = SIMD4<Float>(right.x, up.x, -fwd.x, 0)
        V.columns.1 = SIMD4<Float>(right.y, up.y, -fwd.y, 0)
        V.columns.2 = SIMD4<Float>(right.z, up.z, -fwd.z, 0)
        V.columns.3 = SIMD4<Float>(-simd_dot(right, sunPos), -simd_dot(up, sunPos),
                                   simd_dot(fwd, sunPos), 1)

        // Ortografica l=-1100..1100, b=0..2200, n=1..f=3200 (come QUICK_START,
        // estesa per coprire l'intera area città con margine).
        let l: Float = -1100, r: Float = 1100, b: Float = 0, t: Float = 2200
        let n: Float = 1, f: Float = 3200
        var P = matrix_identity_float4x4
        P.columns.0 = SIMD4<Float>(2 / (r - l), 0, 0, 0)
        P.columns.1 = SIMD4<Float>(0, 2 / (t - b), 0, 0)
        P.columns.2 = SIMD4<Float>(0, 0, 1 / (n - f), 0)
        P.columns.3 = SIMD4<Float>((l + r) / (l - r), (b + t) / (b - t), n / (n - f), 1)

        return ShadowUniforms(
            sunViewProj: P * V,
            sunPosRadius: SIMD4<Float>(sunPos.x, sunPos.y, sunPos.z, 1200),
            biasResolution: SIMD4<Float>(shadowUniforms.biasResolution.x,
                                         shadowUniforms.biasResolution.y, 0, 0))
    }

    private func offscreenPass(scene: MTLTexture, depth: MTLTexture,
                               clear: MTLClearColor) -> MTLRenderPassDescriptor {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = scene
        p.colorAttachments[0].loadAction = .clear
        // L'MSAA del colore viene risolto nella texture 2D leggibile dai post-pass.
        if let resolve = sceneResolveTex {
            p.colorAttachments[0].storeAction = .multisampleResolve
            p.colorAttachments[0].resolveTexture = resolve
        } else {
            p.colorAttachments[0].storeAction = .store
        }
        p.colorAttachments[0].clearColor = clear
        p.depthAttachment.texture = depth
        p.depthAttachment.loadAction = .clear
        p.depthAttachment.storeAction = .dontCare
        p.depthAttachment.clearDepth = 1.0
        return p
    }

    private func simplePass(target: MTLTexture) -> MTLRenderPassDescriptor {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = target
        p.colorAttachments[0].loadAction = .dontCare
        p.colorAttachments[0].storeAction = .store
        return p
    }

    private func ensureTargets(width: Int, height: Int) {
        // Chiamato solo nel ramo Ultra: target HDR + MSAA 4x alla scala richiesta.
        let wantScale: Float = Float(GameSettings.shared.quality.renderScale)
        let w = max(1, Int(Float(width) * wantScale))
        let h = max(1, Int(Float(height) * wantScale))
        if sceneTex != nil && w == texW && h == texH { return }

        let fmt: MTLPixelFormat = .rgba16Float
        let sampleCount = 4
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
        d.sampleCount = sampleCount
        sceneTex = device.makeTexture(descriptor: d)

        // Resolve 2D della scena (campionabile da bright/composite).
        if sampleCount > 1 {
            let rd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: w, height: h, mipmapped: false)
            rd.usage = [.renderTarget, .shaderRead]
            rd.textureType = .type2D
            sceneResolveTex = device.makeTexture(descriptor: rd)
        } else {
            sceneResolveTex = nil
        }

        // Depth MSAA (stessa tessitura del colore).
        let dd = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float,
            width: w, height: h, mipmapped: false)
        dd.usage = .renderTarget
        dd.textureType = sampleCount > 1 ? .type2DMultisample : .type2D
        dd.sampleCount = sampleCount
        depthTex = device.makeTexture(descriptor: dd)

        // Bloom ping-pong a metà risoluzione (sempre 2D, senza MSAA).
        let bw = max(1, w / 2), bh = max(1, h / 2)
        let bd = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: fmt, width: bw, height: bh, mipmapped: false)
        bd.usage = [.renderTarget, .shaderRead]
        bloomA = device.makeTexture(descriptor: bd)
        bloomB = device.makeTexture(descriptor: bd)

        texW = w; texH = h
        prepassScale = wantScale
    }

    private func drawFullscreen(enc: MTLRenderCommandEncoder, pipeline: MTLRenderPipelineState) {
        enc.setRenderPipelineState(pipeline)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    // ------------------------------------------------------------ //

    private func uniformBuffer() -> MTLBuffer {
        if let b = uniformsBuffer {
            b.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<FlyUniforms>.stride)
            return b
        }
        let b = device.makeBuffer(length: MemoryLayout<FlyUniforms>.stride,
                                  options: .storageModeShared)!
        b.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<FlyUniforms>.stride)
        uniformsBuffer = b
        return b
    }
    private var uniformsBuffer: MTLBuffer?

    private weak var attachedView: MTKView?

    private func makeUniforms(aspect: Float, width: Float, height: Float) -> FlyUniforms {
        let cp = fly_cam_pos()
        let cq = fly_cam_quat()
        let w2 = sqrtf(max(0, 1 - cq.x*cq.x - cq.y*cq.y - cq.z*cq.z))
        var camPos = SIMD3<Float>(cp.x, cp.y, cp.z)
        let sh = fly_shake()
        if sh > 0 {
            let t = Float(fly_time()) * 60.0
            camPos += SIMD3<Float>(sin(t*1.1), cos(t*1.7), sin(t*1.3)) * sh * 0.8
        }
        // FOV dinamico quadratico in Mach (Modulo 3 del doc):
        // FOV = base + alpha * min((v/v_mach1)^2, beta) — da 70° a ~103°.
        let v = fly_speed()
        let machT = min(2.44, pow(v / 343.0, 2.0))           // beta = 2.44 (≈ Mach 1.56 saturo)
        var fov = 1.22 + 0.55 * machT / 2.44
        fov += fly_sonic_ripple() * 0.25                     // kick all'onda d'urto
        let proj = MathUtil.perspective(fovY: fov, aspect: aspect, zNear: 0.5, zFar: 2200)
        let view = MathUtil.lookFrom(eye: camPos, quat: SIMD4<Float>(cq.x, cq.y, cq.z, w2))
        let viewProj = proj * view
        let sun = MathUtil.sunDirection(time: Float(fly_time()))
        let fwd = MathUtil.camForward(quat: SIMD4<Float>(cq.x, cq.y, cq.z, w2))
        return FlyUniforms(
            viewProj: viewProj,
            invViewProj: viewProj.inverse,
            cameraPosTime: SIMD4(camPos.x, camPos.y, camPos.z, Float(fly_time())),
            fwdAspect: SIMD4(fwd.x, fwd.y, fwd.z, aspect),
            sunPre: SIMD4(sun.x, sun.y, sun.z, prepassScale),
            bufferSizePad: SIMD4(width, height, 0, 0))
    }

    private func ensure(_ buf: inout MTLBuffer?, capacity: inout Int, needed: Int) -> MTLBuffer {
        if buf == nil || capacity < needed {
            capacity = max(64, needed * 2)
            buf = device.makeBuffer(length: capacity * MemoryLayout<InstanceData>.stride,
                                    options: .storageModeShared)
        }
        return buf!
    }

    // ------------------------------------------------------------ //
    //  Mesh procedurali (sfere, capsule) — niente più cubi per i personaggi

    private func makeSphere(rings: Int, segments: Int) -> (v: [Float], i: [UInt16]) {
        var v: [Float] = []
        var idx: [UInt16] = []
        for r in 0...rings {
            let phi = Float.pi * Float(r) / Float(rings)
            for s in 0..<segments {
                let theta = Float.pi * 2.0 * Float(s) / Float(segments)
                let x = sin(phi) * cos(theta), y = cos(phi), z = sin(phi) * sin(theta)
                v.append(contentsOf: [x, y, z, x, y, z])   // pos + normal
            }
        }
        for r in 0..<rings {
            for s in 0..<segments {
                let a = UInt16(r * segments + s)
                let b = UInt16(r * segments + (s + 1) % segments)
                let c = UInt16((r + 1) * segments + s)
                let d = UInt16((r + 1) * segments + (s + 1) % segments)
                idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return (v, idx)
    }

    private func makeCapsule(segments: Int, rings: Int) -> (v: [Float], i: [UInt16]) {
        // Capsula lungo Y: emisfero sup (y 2→1), cilindro (y 1→-1), emisfero inf (y -1→-2).
        var v: [Float] = []
        var idx: [UInt16] = []
        let rows = rings * 2 + 2
        for r in 0...rows {
            let t = Float(r) / Float(rows)          // 0..1
            let phi: Float
            let y: Float
            if t < 0.25 {
                phi = t / 0.25 * (Float.pi / 2)
                y = cos(phi) + 1                    // 2 → 1
            } else if t > 0.75 {
                phi = (t - 0.75) / 0.25 * (Float.pi / 2) + Float.pi / 2
                y = cos(phi) - 1                    // -1 → -2
            } else {
                phi = Float.pi / 2
                y = 1 - (t - 0.25) / 0.5 * 2        // 1 → -1
            }
            for s in 0..<segments {
                let theta = Float.pi * 2.0 * Float(s) / Float(segments)
                let x = sin(phi) * cos(theta), z = sin(phi) * sin(theta)
                v.append(contentsOf: [x, y, z, x, y, z])
            }
        }
        for r in 0..<rows {
            for s in 0..<segments {
                let a = UInt16(r * segments + s)
                let b = UInt16(r * segments + (s + 1) % segments)
                let c = UInt16((r + 1) * segments + s)
                let d = UInt16((r + 1) * segments + (s + 1) % segments)
                idx.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return (v, idx)
    }

    private func buildMeshes() {
        // Ultra 4K: tessiture più dense (anelli e segmenti extra).
        let ultra = GameSettings.shared.quality == .ultra

        let rings = ultra ? 14 : 10
        let segs = ultra ? 20 : 14
        let sph = makeSphere(rings: rings, segments: segs)
        sphereICount = sph.i.count
        sphereVB = device.makeBuffer(bytes: sph.v, length: sph.v.count * 4, options: .storageModeShared)
        sphereIB = device.makeBuffer(bytes: sph.i, length: sph.i.count * 2, options: .storageModeShared)

        let cap = makeCapsule(segments: ultra ? 14 : 10, rings: ultra ? 6 : 4)
        capsuleICount = cap.i.count
        capsuleVB = device.makeBuffer(bytes: cap.v, length: cap.v.count * 4, options: .storageModeShared)
        capsuleIB = device.makeBuffer(bytes: cap.i, length: cap.i.count * 2, options: .storageModeShared)

        // Indici del mantello (12 quad × 4 vertici). removeAll: la funzione può
        // essere richiamata da applyQuality senza duplicare gli indici.
        capeIndices.removeAll()
        for q in 0..<Self.capeQuadCount {
            let b = UInt16(q * 4)
            capeIndices.append(contentsOf: [b, b+2, b+1, b+1, b+2, b+3])
        }
    }

    private func buildClouds() {
        var list: [InstanceData] = []
        for i in 0..<32 {
            let t = Float(i)
            let ang = t * 2.39996   // golden angle
            let rad = 260 + (t * 61).truncatingRemainder(dividingBy: 620)
            let x = cos(ang) * rad, z = sin(ang) * rad - 420
            let y = 300 + (t * 47).truncatingRemainder(dividingBy: 150)
            let sx = 60 + (t * 23).truncatingRemainder(dividingBy: 80)
            let sz = 40 + (t * 31).truncatingRemainder(dividingBy: 60)
            let m = MathUtil.translate(x: x, y: y, z: z)
                * MathUtil.scaleNonUniform(sx: sx, sy: 7 + (t*7).truncatingRemainder(dividingBy: 6), sz: sz)
            list.append(InstanceData(model: m, color: SIMD4<Float>(1, 1, 1, 1)))
        }
        cloudInstances = list
        cloudBuffer = device.makeBuffer(bytes: list,
                                        length: list.count * MemoryLayout<InstanceData>.stride,
                                        options: .storageModeShared)
    }

    // ------------------------------------------------------------ //
    //  Terra con strada

    private func drawGround(enc: MTLRenderCommandEncoder) {
        let m = MathUtil.translate(x: 0, y: -1.0, z: 0)
            * MathUtil.scaleNonUniform(sx: 1600, sy: 1.0, sz: 2600)
        let inst = InstanceData(model: m, color: SIMD4<Float>(0.30, 0.31, 0.33, 1))
        var instMut = inst
        enc.setVertexBytes(&instMut, length: MemoryLayout<InstanceData>.stride, index: 2)
        var one = Int32(1)
        enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: 1)
    }

    private func drawCity(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_building_count())
        guard n > 0 else { return }
        let buf = ensure(&solidInstances, capacity: &solidCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: solidCapacity)

        var count = 0
        for i in 0..<n {
            var pos = FlyVec3(); var size = FlyVec3(); var hue: Float = 0
            fly_building(Int32(i), &pos, &size, &hue)
            if size.y <= 0 { continue }        // distrutto dal laser
            let m = MathUtil.translate(x: pos.x, y: pos.y + size.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size.x, sy: size.y, sz: size.z)
            // Variazione realistica dei materiali tra edifici.
            let v = sin(hue * 61.7) * 0.5 + 0.5
            let col = SIMD4<Float>(0.46 + 0.14 * v, 0.46 + 0.08 * (1 - v), 0.48 + 0.10 * v, 1)
            ptr[count] = InstanceData(model: m, color: col)
            count += 1
        }
        guard count > 0 else { return }
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: count)
    }

    private func drawClouds(enc: MTLRenderCommandEncoder) {
        guard cloudBuffer != nil, !cloudInstances.isEmpty else { return }
        // Ultra/alta: tutte le nuvole; Media: metà; Lite: niente.
        switch GameSettings.shared.quality {
        case .lite: return
        case .media:
            drawCloudRange(enc: enc, indices: stride(from: 0, to: cloudInstances.count, by: 2))
        case .alta, .ultra:
            let n = min(GameSettings.shared.quality.cloudCount, cloudInstances.count)
            drawCloudRange(enc: enc, indices: 0..<n)
        }
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
    }

    private func drawCloudRange<S: Sequence>(enc: MTLRenderCommandEncoder, indices: S)
        where S.Element == Int {
        enc.setRenderPipelineState(pipelineCloud)
        enc.setDepthStencilState(noDepthState)   // senza scrittura depth: evita pop
        var all: [InstanceData] = []
        for i in indices where i >= 0 && i < cloudInstances.count { all.append(cloudInstances[i]) }
        if all.isEmpty { return }
        if cloudDynamicBuffer == nil || cloudDynamicCapacity < all.count {
            cloudDynamicCapacity = all.count * 2
            cloudDynamicBuffer = device.makeBuffer(length: cloudDynamicCapacity * MemoryLayout<InstanceData>.stride,
                                                   options: .storageModeShared)
        }
        if let dyn = cloudDynamicBuffer {
            all.withUnsafeBytes { raw in
                dyn.contents().copyMemory(from: raw.baseAddress!, byteCount: all.count * MemoryLayout<InstanceData>.stride)
            }
            enc.setVertexBuffer(dyn, offset: 0, index: 2)
            var c = Int32(all.count)
            enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: all.count)
        }
    }
    private var cloudDynamicBuffer: MTLBuffer?
    private var cloudDynamicCapacity = 0

    // ------------------------------------------------------------ //
    //  SUPERMAN: corpo articolato con mesh vere + mantello animato

    private func drawPart(_ enc: MTLRenderCommandEncoder, _ m: simd_float4x4, _ c: SIMD4<Float>,
                          sphere: Bool) {
        var inst = InstanceData(model: m, color: c)
        enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
        let vb = sphere ? sphereVB! : capsuleVB!
        let ib = sphere ? sphereIB! : capsuleIB!
        enc.setVertexBuffer(vb, offset: 0, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: sphere ? sphereICount : capsuleICount,
                                  indexType: .uint16, indexBuffer: ib,
                                  indexBufferOffset: 0, instanceCount: 1)
    }

    private func drawHero(enc: MTLRenderCommandEncoder) {
        let p = fly_player_pos()
        let q = fly_player_quat()
        let qw = sqrtf(max(0, 1 - q.x*q.x - q.y*q.y - q.z*q.z))
        let st = Int(fly_state())
        let flying = st == 1
        let walking = st == 3
        let crashed = st == 2
        let onGround = fly_on_ground() == 1
        let t = Float(fly_time())
        let heroQ = simd_quatf(ix: q.x, iy: q.y, iz: q.z, r: qw)
        // Bounce cinematico: a terra il corpo ondeggia col ciclo del passo.
        let phase = fly_anim_phase()
        let runFactor = min(1.0, fly_speed() / 20.0)          // 0 cammina, 1 corre
        let bounce: Float = walking && onGround
            ? (abs(sin(phase)) * 0.05 + 0.03) * (0.6 + 0.4 * runFactor) : 0
        let root = MathUtil.translate(x: p.x, y: p.y + bounce, z: p.z) * simd_float4x4(heroQ)
        let boosting = flying && fly_speed() > 55

        enc.setRenderPipelineState(pipelineMesh)
        enc.setDepthStencilState(depthState)

        var R = root
        if crashed { R = root * MathUtil.rotateQuat(x: 0, y: 0, z: sin(t*3)/2, w: cos(t*3)/2) }

        let kBlue  = SIMD4<Float>(0.10, 0.22, 0.65, 1)
        let kBlue2 = SIMD4<Float>(0.08, 0.18, 0.55, 1)
        let kRed   = SIMD4<Float>(0.78, 0.08, 0.10, 1)
        let kSkin  = SIMD4<Float>(0.93, 0.75, 0.62, 1)
        let kGold  = SIMD4<Float>(0.95, 0.78, 0.25, 2)   // alpha 2 = emissivo

        // --- pose cinematiche ---
        var legSwing: Float = 0
        var legTuck: Float = 0
        var armSwing: Float = 0
        var lean: Float = 0
        var armSpread: Float = 0        // apertura gomiti (corsa)
        if walking && onGround {
            let moving = fly_speed() > 1.0
            // Ampiezza e frequenza crescono con la corsa; fase dal motore (passi reali).
            let amp = 0.35 + 0.45 * runFactor
            let a: Float = moving ? sin(phase) * amp : 0.06
            legSwing = a
            armSwing = -a * (0.85 + 0.5 * runFactor)
            armSpread = runFactor * 0.5
            // Corsa: busto in avanti (più inclinato più corri) + rollio dolce.
            lean = moving ? (-0.12 - 0.16 * runFactor) + sin(phase * 2.0) * 0.015 : 0
        } else if walking && !onGround {
            // Salto cinematografico: gambe raccolte, braccia aperte in alto.
            legTuck = -0.9; legSwing = -0.35; armSwing = 1.0; armSpread = 0.6; lean = -0.18
        }

        let armFwd: Float = flying ? 1.0 : 0.0

        // torso (capsula): altezza 4*sy, centro a 1.0 → spalle a ~1.36
        let torsoM = R * MathUtil.translate(x: 0, y: 1.00, z: 0)
            * MathUtil.rotateQuat(x: sin(lean/2), y: 0, z: 0, w: cos(lean/2))
        drawPart(enc, torsoM * MathUtil.scaleNonUniform(sx: 0.30, sy: 0.18, sz: 0.20), kBlue, sphere: false)
        // petto/emblema: losanga emissiva (cubo ruotato 45°)
        let emblem = torsoM * MathUtil.translate(x: 0, y: 0.10, z: -0.20)
            * MathUtil.rotateQuat(x: 0, y: 0, z: sin(Float.pi/4), w: cos(Float.pi/4))
            * MathUtil.scaleNonUniform(sx: 0.13, sy: 0.13, sz: 0.05)
        drawPart(enc, emblem, kGold, sphere: false)
        // cintura rossa
        let belt = torsoM * MathUtil.translate(x: 0, y: -0.38, z: 0)
            * MathUtil.scaleNonUniform(sx: 0.30, sy: 0.05, sz: 0.22)
        drawPart(enc, belt, kRed, sphere: false)

        // testa: sfera + naso
        let headM = R * MathUtil.translate(x: 0, y: 1.62 + lean * -0.10, z: 0)
        drawPart(enc, headM * MathUtil.scaleNonUniform(sx: 0.21, sy: 0.24, sz: 0.22), kSkin, sphere: true)
        let hair = headM * MathUtil.translate(x: 0, y: 0.10, z: 0.05)
            * MathUtil.scaleNonUniform(sx: 0.22, sy: 0.12, sz: 0.23)
        drawPart(enc, hair, SIMD4<Float>(0.14, 0.10, 0.07, 1), sphere: false)

        // braccia: spalla→gomito→pugno; in corsa gomiti piegati e contrappeso ampio
        for s: Float in [-1, 1] {
            let swing = armSwing * -s
            let shoulder = R * MathUtil.translate(x: 0.34 * s, y: 1.22, z: 0)
            let angUA = -0.25 - 1.15 * armFwd + swing
            let uaRot = MathUtil.rotateQuat(x: sin(angUA/2), y: 0, z: 0, w: cos(angUA/2))
            let upperLen: Float = 0.30
            let uaM = shoulder * uaRot * MathUtil.translate(x: 0, y: -upperLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.085, sy: upperLen/4, sz: 0.085)
            drawPart(enc, uaM, kBlue, sphere: false)
            let elbow = shoulder * uaRot * MathUtil.translate(x: 0, y: -upperLen, z: 0)
            // Gomito: disteso in volo, piegato in corsa (da cinema), semi in camminata.
            let elbowBend = armFwd > 0.5 ? 0.35 : (0.35 + 1.05 * (1 - runFactor)) - armSpread * 0.5
            let angFA = elbowBend + swing * 0.4
            let faRot = uaRot * MathUtil.rotateQuat(x: sin(angFA/2), y: 0, z: 0, w: cos(angFA/2))
            let foreLen: Float = 0.28
            let faM = elbow * faRot * MathUtil.translate(x: 0, y: -foreLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.075, sy: foreLen/4, sz: 0.075)
            drawPart(enc, faM, kSkin, sphere: false)
            let fistM = elbow * faRot * MathUtil.translate(x: 0, y: -foreLen - 0.05, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.045, sz: 0.10)
            drawPart(enc, fistM, kSkin, sphere: true)
        }

        // gambe: anca→ginocchio→stivale; in corsa il tallone risale verso il gluteo
        for s: Float in [-1, 1] {
            let swing = legSwing * s + legTuck
            let hip = R * MathUtil.translate(x: 0.14 * s, y: 0.62, z: 0)
            let thLen: Float = 0.34
            let thRot = MathUtil.rotateQuat(x: sin(swing/2), y: 0, z: 0, w: cos(swing/2))
            let thM = hip * thRot * MathUtil.translate(x: 0, y: -thLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.11, sy: thLen/4, sz: 0.11)
            drawPart(enc, thM, kBlue2, sphere: false)
            let knee = hip * thRot * MathUtil.translate(x: 0, y: -thLen, z: 0)
            // Ginocchio: dietro quando la gamba va indietro; recupero ampio in corsa.
            let kneeBend = max(0, -swing) * 0.6 + runFactor * max(0, -swing) * 1.6
            let shinRot = thRot * MathUtil.rotateQuat(x: sin(kneeBend / 2), y: 0, z: 0, w: cos(kneeBend / 2))
            let shLen: Float = 0.30
            let shM = knee * shinRot * MathUtil.translate(x: 0, y: -shLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.09, sy: shLen/4, sz: 0.09)
            drawPart(enc, shM, kBlue2, sphere: false)
            let footM = knee * shinRot * MathUtil.translate(x: 0, y: -shLen - 0.05, z: -0.05)
                * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.05, sz: 0.20)
            drawPart(enc, footM, kRed, sphere: false)
        }

        // --- mantello animato (buffer vertici ricostruito ogni frame) ---
        // In corsa il mantello sventola dietro, quasi orizzontale (cinematico).
        let capeWind = flying
            ? (0.55 + 0.45 * min(1, fly_speed() / 80.0))
            : (0.3 + 0.7 * runFactor)
        let capeLift = flying ? 0.55 : 0.25 * runFactor
        drawCape(enc: enc, root: R, t: t, flying: flying || (walking && runFactor > 0.6),
                 wind: capeWind, lift: capeLift)

        // fiamma del boost
        if boosting {
            var inst = InstanceData(
                model: R * MathUtil.translate(x: 0, y: 0.55, z: 0.62)
                    * MathUtil.scaleNonUniform(sx: 0.16, sy: 0.16, sz: 0.9 + 0.25 * sin(t * 31)),
                color: SIMD4<Float>(0.55, 0.8, 1.0, 0.8))
            enc.setRenderPipelineState(pipelineGlow)
            enc.setDepthStencilState(noDepthState)
            enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: 1)
            enc.setRenderPipelineState(pipelineMesh)
            enc.setDepthStencilState(depthState)
        }
    }

    private func drawCape(enc: MTLRenderCommandEncoder, root: simd_float4x4, t: Float,
                          flying: Bool, wind: Float, lift: Float) {
        // Griglia 5×4 punti → 12 quad, animati a mano (onde + flare).
        var verts: [Float] = []
        var grid: [SIMD3<Float>] = Array(repeating: .zero, count: 5 * 4)
        for r in 0...4 {
            let fr = Float(r)
            let sway = sin(t * 6.0 - fr * 0.9) * (0.05 + 0.13 * fr) * wind
            let flare = 0.24 + 0.055 * fr + (flying ? 0 : wind * 0.02)
            let y = 1.30 - (0.34 * fr + fr * fr * 0.02) + lift * fr * 0.35
            let z = 0.26 + 0.055 * fr + abs(sway) * 0.6
            for c in 0...3 {
                let fc = Float(c)
                let x = (fc - 1.5) / 1.5 * (0.30 + 0.05 * fr)   // da -w a +w su 4 colonne
                let px = x * (1.0 + 0.18 * fr) + sin(t * 4.3 - fr * 1.3 + fc) * 0.02 * fr * wind
                let pz = z + sway * (0.4 + 0.2 * fc)
                let py = y + (flying ? sin(t * 5.0 - fr) * 0.02 * fr : 0)
                grid[r * 4 + c] = SIMD3<Float>(px, py, pz)
            }
        }
        // Costruisci i 12 quad (pos+normal+uv): 48 vertici.
        var vi = 0
        for q in 0..<Self.capeQuadCount {
            let r = q / 3, c = q % 3
            let a = grid[r * 4 + c]
            let b = grid[r * 4 + c + 1]
            let d = grid[(r + 1) * 4 + c]
            let e = grid[(r + 1) * 4 + c + 1]
            let n = simd_normalize(simd_cross(b - a, d - a))
            let u0 = Float(c) / 3.0, u1 = Float(c + 1) / 3.0
            let v0 = 1.0 - Float(r) / 4.0, v1 = 1.0 - Float(r + 1) / 4.0
            func push(_ p: SIMD3<Float>, _ uv: (Float, Float)) {
                verts.append(contentsOf: [p.x, p.y, p.z, n.x, n.y, n.z, uv.0, uv.1])
                vi += 1
            }
            push(a, (u0, v0)); push(b, (u1, v0)); push(d, (u0, v1)); push(e, (u1, v1))
        }
        _ = vi
        if capeVB == nil || capeVB.length < verts.count * 4 {
            capeVB = device.makeBuffer(length: verts.count * 4 * 4, options: .storageModeShared)
        }
        capeVB!.contents().copyMemory(from: verts, byteCount: verts.count * 4)

        // Indici statici
        var idxBuf: MTLBuffer
        if let b = capeIndexBuffer { idxBuf = b } else {
            let b = device.makeBuffer(bytes: capeIndices, length: capeIndices.count * 2,
                                      options: .storageModeShared)!
            capeIndexBuffer = b
            idxBuf = b
        }

        enc.setRenderPipelineState(pipelineCape)
        enc.setDepthStencilState(depthState)
        enc.setVertexBuffer(capeVB!, offset: 0, index: 0)
        // Il mantello è definito in spazio root: la matrice modello è root stessa.
        var model = InstanceData(model: root, color: SIMD4<Float>(0.72, 0.07, 0.09, 1))
        enc.setVertexBytes(&model, length: MemoryLayout<InstanceData>.stride, index: 2)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: capeIndices.count,
                                  indexType: .uint16, indexBuffer: idxBuf,
                                  indexBufferOffset: 0, instanceCount: 1)
    }
    private var capeIndexBuffer: MTLBuffer?

    // ------------------------------------------------------------ //
    //  NPC pedoni

    private func drawNpcs(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_npc_count())
        guard n > 0 else { return }
        enc.setRenderPipelineState(pipelineMesh)
        enc.setDepthStencilState(depthState)

        for i in 0..<n {
            var pos = FlyVec3(); var yaw: Float = 0; var phase: Float = 0
            var flee: Int32 = 0; var tint: Float = 0
            fly_npc(Int32(i), &pos, &yaw, &phase, &flee, &tint)

            let cq = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            let R = MathUtil.translate(x: pos.x, y: pos.y, z: pos.z) * simd_float4x4(cq)

            // Colori variati per pedone.
            let shirt = SIMD4<Float>(0.25 + 0.5 * tint, 0.30 + 0.2 * (1 - tint), 0.55 - 0.3 * tint, 1)
            let pants = SIMD4<Float>(0.18, 0.19, 0.24, 1)
            let skin  = SIMD4<Float>(0.90, 0.72, 0.58, 1)
            let hairC = SIMD4<Float>(0.12 + 0.2 * tint, 0.09, 0.06, 1)

            let s = sin(phase), c2 = cos(phase)
            let swing: Float = flee == 1 ? s * 0.95 : s * 0.45
            let armRaise: Float = flee == 1 ? -2.4 : 0   // braccia in su nel panico

            // gambe
            for g: Float in [-1, 1] {
                let sw = swing * g
                let hip = R * MathUtil.translate(x: 0.09 * g, y: 0.46, z: 0)
                let thRot = MathUtil.rotateQuat(x: sin(sw/2), y: 0, z: 0, w: cos(sw/2))
                let thM = hip * thRot * MathUtil.translate(x: 0, y: -0.115, z: 0)
                    * MathUtil.scaleNonUniform(sx: 0.055, sy: 0.055, sz: 0.055)
                drawPart(enc, thM, pants, sphere: false)
                let footM = hip * thRot * MathUtil.translate(x: 0, y: -0.26, z: 0)
                    * MathUtil.scaleNonUniform(sx: 0.05, sy: 0.028, sz: 0.09)
                drawPart(enc, footM, SIMD4<Float>(0.1, 0.1, 0.12, 1), sphere: false)
            }
            // torso
            let torsoM = R * MathUtil.translate(x: 0, y: 0.72, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.13, sy: 0.09, sz: 0.09)
            drawPart(enc, torsoM, shirt, sphere: false)
            // testa + capelli
            let headM = R * MathUtil.translate(x: 0, y: 1.02, z: 0)
            drawPart(enc, headM * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.11, sz: 0.10), skin, sphere: true)
            let hairM = headM * MathUtil.translate(x: 0, y: 0.05, z: 0.02)
                * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.05, sz: 0.10)
            drawPart(enc, hairM, hairC, sphere: false)
            // braccia
            for g: Float in [-1, 1] {
                let sw = -swing * g
                let sh = R * MathUtil.translate(x: 0.17 * g, y: 0.88, z: 0)
                let rot = MathUtil.rotateQuat(x: sin((sw + armRaise)/2), y: 0, z: 0, w: cos((sw + armRaise)/2))
                let am = sh * rot * MathUtil.translate(x: 0, y: -0.12, z: 0)
                    * MathUtil.scaleNonUniform(sx: 0.045, sy: 0.055, sz: 0.045)
                drawPart(enc, am, shirt, sphere: false)
            }
        }
    }

    // ------------------------------------------------------------ //
    //  Detriti: cubetti di cemento con tumble che cadono e restano a terra

    private func drawDebris(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_debris_count())
        guard n > 0 else { return }
        let buf = ensure(&solidInstances, capacity: &solidCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: solidCapacity)

        for i in 0..<n {
            var pos = FlyVec3(); var size = FlyVec3()
            var spin: Float = 0; var axis: Float = 0
            fly_debris(Int32(i), &pos, &size, &spin, &axis)
            let m = MathUtil.translate(x: pos.x, y: pos.y, z: pos.z)
                * MathUtil.rotateQuat(x: 0, y: sin(spin / 2), z: 0, w: cos(spin / 2))
                * MathUtil.rotateQuat(x: sin(axis / 2), y: 0, z: 0, w: cos(axis / 2))
                * MathUtil.scaleNonUniform(sx: size.x, sy: size.y, sz: size.z)
            ptr[i] = InstanceData(model: m,
                                  color: SIMD4<Float>(0.42, 0.42, 0.44, 1))   // cemento
        }
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var c = Int32(n)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: n)
    }

    // ------------------------------------------------------------ //
    //  Anelli / laser / particelle (glow additivo)

    private func drawRings(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_ring_count())
        guard n > 0 else { return }
        let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)
        var count = 0
        for i in 0..<n {
            var pos = FlyVec3(); var q = FlyVec3(); var radius: Float = 0
            var passed: Int32 = 0
            fly_ring(Int32(i), &pos, &q, &radius, &passed)
            if passed == 1 { continue }
            let qw = sqrtf(max(0, 1 - q.x*q.x - q.y*q.y - q.z*q.z))
            let m = MathUtil.translate(x: pos.x, y: pos.y, z: pos.z)
                * MathUtil.rotateQuat(x: q.x, y: q.y, z: q.z, w: qw)
                * MathUtil.scaleNonUniform(sx: radius, sy: radius, sz: 1.5)
            let pulse = 0.75 + 0.25 * sin(uniforms.time * 4 + Float(i))
            ptr[count] = InstanceData(model: m, color: SIMD4<Float>(0.3, 0.95, 1.0, 0.9 * pulse))
            count += 1
        }
        guard count > 0 else { return }
        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: count)
    }

    private func drawLaser(enc: MTLRenderCommandEncoder) {
        let active = fly_laser_active() == 1
        let segs = Int(fly_laser_seg_count())
        let need = (active ? 2 : 0) + segs
        guard need > 0 else { return }

        // Un'unica allocazione per il frame: evita ptr steli dopo realloc.
        let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: need)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)
        var count = 0

        if active {
            var eye = FlyVec3(); var end = FlyVec3(); var heat: Float = 0
            var a: Int32 = 0
            fly_laser(&eye, &end, &a, &heat)
            let flicker = 0.85 + 0.15 * sin(uniforms.time * 90)
            let e3 = SIMD3<Float>(eye.x, eye.y, eye.z)
            let d3 = SIMD3<Float>(end.x, end.y, end.z)
            ptr[count] = InstanceData(model: beamMatrix(from: e3, to: d3,
                                                        width: 0.30 + 0.25 * heat),
                                      color: SIMD4<Float>(1.0, 0.15, 0.1, 0.95 * flicker))
            count += 1
            ptr[count] = InstanceData(model: beamMatrix(from: e3, to: d3,
                                                        width: 0.7 + 0.4 * heat),
                                      color: SIMD4<Float>(1.0, 0.4, 0.3, 0.35 * flicker))
            count += 1
        }
        for i in 0..<segs {
            var a = FlyVec3(); var b = FlyVec3(); var w: Float = 0; var life: Float = 0
            fly_laser_seg(Int32(i), &a, &b, &w, &life)
            ptr[count] = InstanceData(
                model: beamMatrix(from: SIMD3<Float>(a.x, a.y, a.z),
                                  to: SIMD3<Float>(b.x, b.y, b.z), width: w * life),
                color: SIMD4<Float>(1.0, 0.2, 0.12, 0.35 * life))
            count += 1
        }
        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(glowInstances, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: count)
    }

    /// Onda d'urto del boom sonico: anello di glow che si espande dal giocatore (§2.2).
    private func drawSonicBoom(enc: MTLRenderCommandEncoder) {
        let ripple = fly_sonic_ripple()
        guard ripple > 0.01 else { return }
        let p = fly_player_pos()
        let q = fly_player_quat()
        let qw = sqrtf(max(0, 1 - q.x*q.x - q.y*q.y - q.z*q.z))
        // Anello orientato come il giocatore, che si allarga e sfuma.
        let radius = (1.0 - ripple) * 260.0 + 8.0
        let m = MathUtil.translate(x: p.x, y: p.y, z: p.z)
            * MathUtil.rotateQuat(x: q.x, y: q.y, z: q.z, w: qw)
            * MathUtil.scaleNonUniform(sx: radius, sy: radius, sz: 1.5)
        var inst = InstanceData(model: m,
                                color: SIMD4<Float>(0.75, 0.9, 1.0, ripple * 0.85))
        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
        var one = Int32(1)
        enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: 1)
    }

    private func beamMatrix(from: SIMD3<Float>, to: SIMD3<Float>, width: Float) -> simd_float4x4 {
        let dir = to - from
        let len = max(0.1, simd_length(dir))
        let d = dir / len
        let w = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if abs(simd_dot(d, SIMD3<Float>(0, 0, -1))) < 0.999 {
            q = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: d)
        } else { q = w }
        let mid = (from + to) * 0.5
        return MathUtil.translate(x: mid.x, y: mid.y, z: mid.z)
            * simd_float4x4(q)
            * MathUtil.scaleNonUniform(sx: width, sy: width, sz: len * 0.5)
    }

    private func drawParticles(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_particle_count())
        guard n > 0 else { return }
        let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)
        // Qualità Lite: mostra solo metà particelle (il motore ne limita comunque il numero).
        let stride = GameSettings.shared.quality == .lite ? 2 : 1
        var count = 0
        var i = 0
        while i < n {
            var pos = FlyVec3(); var size: Float = 0; var life: Float = 0; var hue: Float = 0
            fly_particle(Int32(i), &pos, &size, &life, &hue)
            let m = MathUtil.translate(x: pos.x, y: pos.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size, sy: size, sz: size)
            let c: SIMD4<Float> = hue < 0.05
                ? SIMD4<Float>(1.0, 0.35, 0.1, life * 0.9)
                : SIMD4<Float>(1.0, 0.75, 0.3, life * 0.85)
            ptr[count] = InstanceData(model: m, color: c)
            count += 1
            i += stride
        }
        guard count > 0 else { return }
        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var ic = Int32(count)
        enc.setVertexBytes(&ic, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36, instanceCount: count)
    }
}

// Utility matematiche Swift (allineate con la libreria C++)
enum MathUtil {
    static func perspective(fovY: Float, aspect: Float, zNear: Float, zFar: Float) -> simd_float4x4 {
        var P = matrix_identity_float4x4
        let f = 1 / tan(fovY * 0.5)
        let nd = 1 / (zNear - zFar)
        P.columns.0 = SIMD4<Float>(f / aspect, 0, 0, 0)
        P.columns.1 = SIMD4<Float>(0, f, 0, 0)
        P.columns.2 = SIMD4<Float>(0, 0, zFar * nd, -1)
        P.columns.3 = SIMD4<Float>(0, 0, zNear * zFar * nd, 0)
        return P
    }

    static func lookFrom(eye: SIMD3<Float>, quat: SIMD4<Float>) -> simd_float4x4 {
        let q = simd_quatf(ix: quat.x, iy: quat.y, iz: quat.z, r: quat.w)
        let right = q.act(SIMD3<Float>(1, 0, 0))
        let up = q.act(SIMD3<Float>(0, 1, 0))
        let fwd = q.act(SIMD3<Float>(0, 0, -1))
        var V = matrix_identity_float4x4
        V.columns.0 = SIMD4<Float>(right.x, up.x, -fwd.x, 0)
        V.columns.1 = SIMD4<Float>(right.y, up.y, -fwd.y, 0)
        V.columns.2 = SIMD4<Float>(right.z, up.z, -fwd.z, 0)
        V.columns.3 = SIMD4<Float>(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(fwd, eye), 1)
        return V
    }

    static func translate(x: Float, y: Float, z: Float) -> simd_float4x4 {
        var T = matrix_identity_float4x4
        T.columns.3 = SIMD4<Float>(x, y, z, 1)
        return T
    }

    static func scaleNonUniform(sx: Float, sy: Float, sz: Float) -> simd_float4x4 {
        var S = matrix_identity_float4x4
        S.columns.0.x = sx; S.columns.1.y = sy; S.columns.2.z = sz
        return S
    }

    static func rotateQuat(x: Float, y: Float, z: Float, w: Float) -> simd_float4x4 {
        return simd_float4x4(simd_quatf(ix: x, iy: y, iz: z, r: w))
    }

    /// Direzione di vista della camera (per il cielo procedurale).
    static func camForward(quat: SIMD4<Float>) -> SIMD3<Float> {
        let q = simd_quatf(ix: quat.x, iy: quat.y, iz: quat.z, r: quat.w)
        return q.act(SIMD3<Float>(0, 0, -1))
    }

    /// Sole che sorge/tramonta lentamente col tempo di gioco (ciclo ~4 minuti).
    static func sunDirection(time: Float) -> SIMD3<Float> {
        let ang = time * 0.026            // un ciclo completo ≈ 4 minuti
        return SIMD3<Float>(sin(ang) * 0.8, sin(ang) * 0.55 + 0.30, cos(ang) * 0.8 - 0.3)
    }
}

// Renderer.swift — rendering 3D Metal: Superman con mesh articolate, mantello
// animato, NPC pedoni, città con strade/nuvole/cielo, raggi oculari.

import MetalKit
import simd

struct FlyUniforms {
    var viewProj: simd_float4x4
    var cameraPos: SIMD3<Float>
    var time: Float
    var pad: SIMD3<Float> = .zero
}

struct InstanceData {
    var model: simd_float4x4
    var color: SIMD4<Float>
}

final class Renderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var pipelineCity: MTLRenderPipelineState!    // cubi istanziati (edifici/terra)
    var pipelineMesh: MTLRenderPipelineState!    // mesh personaggi
    var pipelineCape: MTLRenderPipelineState!    // mantello animato
    var pipelineCloud: MTLRenderPipelineState!   // nuvole
    var pipelineGlow: MTLRenderPipelineState!    // anelli/laser/particelle
    var depthState: MTLDepthStencilState!
    var noDepthState: MTLDepthStencilState!

    var bestScore = 0

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
        viewProj: matrix_identity_float4x4, cameraPos: .zero, time: 0)

    init(metalKitView: MTKView) {
        device = metalKitView.device!
        commandQueue = device.makeCommandQueue()!
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

        func makePipe(_ vs: MTLFunction, _ fs: MTLFunction,
                      additive: Bool, depthFormat: MTLPixelFormat) -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = vs
            d.fragmentFunction = fs
            d.colorAttachments[0].pixelFormat = view.colorPixelFormat
            d.colorAttachments[0].isBlendingEnabled = true
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
            d.depthAttachmentPixelFormat = depthFormat
            return (try? device.makeRenderPipelineState(descriptor: d))!
        }

        let df = view.depthStencilPixelFormat
        pipelineCity = makePipe(vsCube, fsCity, additive: false, depthFormat: df)
        pipelineMesh = makePipe(vsMesh, fsFab, additive: false, depthFormat: df)
        pipelineCape = makePipe(vsCape, fsFab, additive: false, depthFormat: df)
        pipelineCloud = makePipe(vsCube, fsCloud, additive: false, depthFormat: df)
        pipelineGlow = makePipe(vsCube, fsGlow, additive: true, depthFormat: df)

        let dsd = MTLDepthStencilDescriptor()
        dsd.depthCompareFunction = .less
        dsd.isDepthWriteEnabled = true
        depthState = device.makeDepthStencilState(descriptor: dsd)!
        let dsd2 = MTLDepthStencilDescriptor()
        dsd2.depthCompareFunction = .less
        dsd2.isDepthWriteEnabled = false
        noDepthState = device.makeDepthStencilState(descriptor: dsd2)!
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        fly_update(1.0 / Double(view.preferredFramesPerSecond),
                   Int32(view.drawableSize.width),
                   Int32(view.drawableSize.height))
        bestScore = max(bestScore, Int(fly_best()))

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let aspect = Float(view.drawableSize.width / max(1.0, view.drawableSize.height))
        uniforms = makeUniforms(aspect: aspect)

        // Cielo in base alla qualità: Alta = tramonto caldo, Media = pomeriggio, Lite = piatto
        switch GameSettings.shared.quality {
        case .alta:
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.36, green: 0.52, blue: 0.88, alpha: 1)
        case .media:
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.42, green: 0.60, blue: 0.90, alpha: 1)
        case .lite:
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.55, green: 0.68, blue: 0.92, alpha: 1)
        }

        enc.setVertexBuffer(uniformBuffer(), offset: 0, index: 1)
        enc.setCullMode(.none)

        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        drawGround(enc: enc)
        drawCity(enc: enc)
        drawClouds(enc: enc)
        drawHero(enc: enc)
        drawNpcs(enc: enc)
        drawRings(enc: enc)
        drawLaser(enc: enc)
        drawParticles(enc: enc)

        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
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

    private func makeUniforms(aspect: Float) -> FlyUniforms {
        let cp = fly_cam_pos()
        let cq = fly_cam_quat()
        let w2 = sqrtf(max(0, 1 - cq.x*cq.x - cq.y*cq.y - cq.z*cq.z))
        var camPos = SIMD3<Float>(cp.x, cp.y, cp.z)
        let sh = fly_shake()
        if sh > 0 {
            let t = Float(fly_time()) * 60.0
            camPos += SIMD3<Float>(sin(t*1.1), cos(t*1.7), sin(t*1.3)) * sh * 0.8
        }
        let proj = MathUtil.perspective(fovY: 1.22, aspect: aspect, zNear: 0.5, zFar: 2200)
        let view = MathUtil.lookFrom(eye: camPos, quat: SIMD4<Float>(cq.x, cq.y, cq.z, w2))
        return FlyUniforms(viewProj: proj * view, cameraPos: camPos, time: Float(fly_time()))
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
        let sph = makeSphere(rings: 10, segments: 14)
        sphereICount = sph.i.count
        sphereVB = device.makeBuffer(bytes: sph.v, length: sph.v.count * 4, options: .storageModeShared)
        sphereIB = device.makeBuffer(bytes: sph.i, length: sph.i.count * 2, options: .storageModeShared)

        let cap = makeCapsule(segments: 10, rings: 4)
        capsuleICount = cap.i.count
        capsuleVB = device.makeBuffer(bytes: cap.v, length: cap.v.count * 4, options: .storageModeShared)
        capsuleIB = device.makeBuffer(bytes: cap.i, length: cap.i.count * 2, options: .storageModeShared)

        // Indici del mantello (16 quad × 4 vertici).
        for q in 0..<Self.capeQuadCount {
            let b = UInt16(q * 4)
            capeIndices.append(contentsOf: [b, b+2, b+1, b+1, b+2, b+3])
        }
    }

    private func buildClouds() {
        var list: [InstanceData] = []
        for i in 0..<22 {
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
        guard let cb = cloudBuffer, !cloudInstances.isEmpty else { return }
        // Media: una nuvola su due; Lite: niente nuvole.
        switch GameSettings.shared.quality {
        case .lite: return
        case .media:
            var half = [InstanceData]()
            for (i, inst) in cloudInstances.enumerated() where i % 2 == 0 { half.append(inst) }
            if cloudCapacity < half.count {
                cloudCapacity = half.count * 2
                cloudDynamicBuffer = device.makeBuffer(length: cloudCapacity * MemoryLayout<InstanceData>.stride,
                                                       options: .storageModeShared)
            }
            if let dyn = cloudDynamicBuffer {
                dyn.contents().copyMemory(from: half, byteCount: half.count * MemoryLayout<InstanceData>.stride)
                enc.setRenderPipelineState(pipelineCloud)
                enc.setDepthStencilState(noDepthState)
                enc.setVertexBuffer(dyn, offset: 0, index: 2)
                var c = Int32(half.count)
                enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                                   instanceCount: half.count)
            }
        case .alta:
            enc.setRenderPipelineState(pipelineCloud)
            enc.setDepthStencilState(noDepthState)   // senza scrittura depth: evita pop
            enc.setVertexBuffer(cb, offset: 0, index: 2)
            var c = Int32(cloudInstances.count)
            enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                               instanceCount: cloudInstances.count)
        }
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
    }
    private var cloudDynamicBuffer: MTLBuffer?
    private var cloudCapacity = 0

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
        let root = MathUtil.translate(x: p.x, y: p.y, z: p.z) * simd_float4x4(heroQ)
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

        // --- pose ---
        var legSwing: Float = 0
        var legTuck: Float = 0
        var armSwing: Float = 0
        var lean: Float = 0
        if walking && onGround {
            let moving = fly_speed() > 1.0
            let a: Float = moving ? sin(t * 10.0) * 0.65 : 0.06
            legSwing = a
            armSwing = -a * 0.8
            lean = moving ? -0.10 : 0
        } else if walking && !onGround {
            legTuck = -0.8; legSwing = -0.3; armSwing = 0.9; lean = -0.15
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

        // braccia: spalla→gomito→pugno (capsule: sy = L/4, centro a -L/2)
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
            let angFA = 0.35 + 1.05 * armFwd
            let faRot = uaRot * MathUtil.rotateQuat(x: sin(angFA/2), y: 0, z: 0, w: cos(angFA/2))
            let foreLen: Float = 0.28
            let faM = elbow * faRot * MathUtil.translate(x: 0, y: -foreLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.075, sy: foreLen/4, sz: 0.075)
            drawPart(enc, faM, kSkin, sphere: false)
            let fistM = elbow * faRot * MathUtil.translate(x: 0, y: -foreLen - 0.05, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.045, sz: 0.10)
            drawPart(enc, fistM, kSkin, sphere: true)
        }

        // gambe: anca→ginocchio→stivale (capsule: sy = L/4)
        for s: Float in [-1, 1] {
            let swing = legSwing * s + legTuck
            let hip = R * MathUtil.translate(x: 0.14 * s, y: 0.62, z: 0)
            let thLen: Float = 0.34
            let thRot = MathUtil.rotateQuat(x: sin(swing/2), y: 0, z: 0, w: cos(swing/2))
            let thM = hip * thRot * MathUtil.translate(x: 0, y: -thLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.11, sy: thLen/4, sz: 0.11)
            drawPart(enc, thM, kBlue2, sphere: false)
            let knee = hip * thRot * MathUtil.translate(x: 0, y: -thLen, z: 0)
            let shinRot = thRot * MathUtil.rotateQuat(x: sin(max(0, -swing) * 0.6 / 2), y: 0, z: 0, w: cos(max(0, -swing) * 0.6 / 2))
            let shLen: Float = 0.30
            let shM = knee * shinRot * MathUtil.translate(x: 0, y: -shLen/2, z: 0)
                * MathUtil.scaleNonUniform(sx: 0.09, sy: shLen/4, sz: 0.09)
            drawPart(enc, shM, kBlue2, sphere: false)
            let footM = knee * shinRot * MathUtil.translate(x: 0, y: -shLen - 0.05, z: -0.05)
                * MathUtil.scaleNonUniform(sx: 0.10, sy: 0.05, sz: 0.20)
            drawPart(enc, footM, kRed, sphere: false)
        }

        // --- mantello animato (buffer vertici ricostruito ogni frame) ---
        drawCape(enc: enc, root: R, t: t, flying: flying,
                 wind: flying ? (0.55 + 0.45 * min(1, fly_speed() / 80.0)) : 0.25,
                 lift: flying ? 0.55 : 0.0)

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
}

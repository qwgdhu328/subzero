// Renderer.swift — rendering 3D Metal: Superman animato, città, laser oculari,
// anelli, particelle. Il personaggio è costruito a runtime (vertici wrapper).

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
    var pipelineCity: MTLRenderPipelineState!
    var pipelineGlow: MTLRenderPipelineState!
    var depthState: MTLDepthStencilState!
    var noDepthState: MTLDepthStencilState!

    var bestScore = 0

    // Buffer istanze (riusati, mai riallocati se non serve)
    private var solidInstances: MTLBuffer?
    private var glowInstances: MTLBuffer?
    private var solidCapacity = 512
    private var glowCapacity = 256

    // Mesh del personaggio: 8 vertici → 6 facce quads → 24 vertici/36 indici
    private var heroMesh: (verts: [Float], tris: [UInt16]) = ([], [])
    private var heroVertexBuffer: MTLBuffer?
    private var heroIndexBuffer: MTLBuffer?

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
        buildHeroMesh()
    }

    private func buildPipelines(library: MTLLibrary?, view: MTKView) {
        guard let lib = library else {
            fatalError("Metal library non trovata: controlla Shaders.metal nel target")
        }
        let vsFn = lib.makeFunction(name: "vertexMain")!
        let fsFn = lib.makeFunction(name: "fragmentMain")!
        let glowFn = lib.makeFunction(name: "glowFragment")!

        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = vsFn
        d.fragmentFunction = fsFn
        d.colorAttachments[0].pixelFormat = view.colorPixelFormat
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].rgbBlendOperation = .add
        d.colorAttachments[0].alphaBlendOperation = .add
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineCity = try! device.makeRenderPipelineState(descriptor: d)

        let d2 = MTLRenderPipelineDescriptor()
        d2.vertexFunction = vsFn
        d2.fragmentFunction = glowFn
        d2.colorAttachments[0].pixelFormat = view.colorPixelFormat
        d2.colorAttachments[0].isBlendingEnabled = true
        d2.colorAttachments[0].rgbBlendOperation = .add
        d2.colorAttachments[0].alphaBlendOperation = .add
        d2.colorAttachments[0].sourceRGBBlendFactor = .one
        d2.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d2.colorAttachments[0].sourceAlphaBlendFactor = .one
        d2.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d2.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        pipelineGlow = try! device.makeRenderPipelineState(descriptor: d2)

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
        // 1) motore C++: update a timestep fisso
        fly_update(1.0 / Double(view.preferredFramesPerSecond),
                   Int32(view.drawableSize.width),
                   Int32(view.drawableSize.height))

        // punteggio best per il restart
        bestScore = max(bestScore, Int(fly_best()))

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let aspect = Float(view.drawableSize.width / max(1.0, view.drawableSize.height))
        uniforms = makeUniforms(aspect: aspect)

        // Cielo: clear color tramonto
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.42, green: 0.58, blue: 0.86, alpha: 1)

        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.none)
        enc.setVertexBuffer(uniformBuffer(), offset: 0, index: 1)

        drawCity(enc: enc)
        drawHero(enc: enc)
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

        let proj = MathUtil.perspective(fovY: 1.22, aspect: aspect, zNear: 0.5, zFar: 1600)
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
    //  Edifici (con danni da laser veicolati in color.a)

    private func drawCity(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_building_count())
        guard n > 0 else { return }
        let buf = ensure(&solidInstances, capacity: &solidCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: solidCapacity)

        var count = 0
        for i in 0..<n {
            var pos = FlyVec3(); var size = FlyVec3(); var hue: Float = 0
            fly_building(Int32(i), &pos, &size, &hue)
            if size.y <= 0 { continue }        // distrutto dal laser: sparito
            let m = MathUtil.translate(x: pos.x, y: pos.y + size.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size.x, sy: size.y, sz: size.z)
            ptr[count] = InstanceData(model: m,
                                      color: windowColor(hue: hue, height: size.y))
            count += 1
        }
        guard count > 0 else { return }

        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: count)
    }

    private func windowColor(hue: Float, height: Float) -> SIMD4<Float> {
        return SIMD4<Float>(0.52, 0.54, 0.58, 1)   // cemento; le finestre le fa lo shader
    }

    // ------------------------------------------------------------ //
    //  SUPERMAN: corpo articolato + mantello animato + pose di volo

    private func buildHeroMesh() {
        // 8 vertici del cubo unitario [-1,1]
        let V: [SIMD3<Float>] = [
            [-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],
            [-1,-1, 1],[1,-1, 1],[1,1, 1],[-1,1, 1]]
        let F: [[Int]] = [
            [0,3,2,1],[4,5,6,7],[0,1,5,4],[2,3,7,6],[1,2,6,5],[0,4,7,3]]
        var verts: [Float] = []
        var tris: [UInt16] = []
        for f in F {
            let base = UInt16(verts.count / 3)
            for i in f { verts.append(contentsOf: [V[i].x, V[i].y, V[i].z]) }
            tris.append(contentsOf: [base, base+1, base+2, base, base+2, base+3])
        }
        heroMesh = (verts, tris)
        heroVertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * 4, options: .storageModeShared)
        heroIndexBuffer = device.makeBuffer(bytes: tris, length: tris.count * 2, options: .storageModeShared)
    }

    /// Matrice part: posizione locale (in metri, asse -Z = avanti), rotazione e scala.
    private func part(_ parent: simd_float4x4, _ pos: SIMD3<Float>,
                      _ rotY: Float = 0, _ rotX: Float = 0, _ rotZ: Float = 0,
                      _ scale: SIMD3<Float>) -> simd_float4x4 {
        parent * MathUtil.translate(x: pos.x, y: pos.y, z: pos.z)
            * MathUtil.rotateQuat(x: 0, y: sin(rotY/2), z: 0, w: cos(rotY/2))
            * MathUtil.rotateQuat(x: sin(rotX/2), y: 0, z: 0, w: cos(rotX/2))
            * MathUtil.rotateQuat(x: 0, y: 0, z: sin(rotZ/2), w: cos(rotZ/2))
            * MathUtil.scaleNonUniform(sx: scale.x, sy: scale.y, sz: scale.z)
    }

    private func drawHero(enc: MTLRenderCommandEncoder) {
        let p = fly_player_pos()
        let q = fly_player_quat()
        let qw = sqrtf(max(0, 1 - q.x*q.x - q.y*q.y - q.z*q.z))
        let flying = Int(fly_state()) == 1
        let t = Float(fly_time())
        let heroQ = simd_quatf(ix: q.x, iy: q.y, iz: q.z, r: qw)
        let root = MathUtil.translate(x: p.x, y: p.y, z: p.z) * simd_float4x4(heroQ)
        let boosting = fly_boost() < 0.999 && fly_speed() > 50

        // Fiamma del boost (glow, disegnata dopo).
        var boostGlow: (m: simd_float4x4, c: SIMD4<Float>)? = nil
        if boosting {
            let fm = root * MathUtil.translate(x: 0, y: -0.1, z: 1.9)
                * MathUtil.scaleNonUniform(sx: 0.35, sy: 0.35, sz: 2.2 + 0.6 * sin(t*31))
            boostGlow = (fm, SIMD4<Float>(0.55, 0.8, 1.0, 0.85))
        }

        var R = root
        if !flying { R = root * MathUtil.rotateQuat(x: 0, y: 0, z: sin(t*3)/2, w: cos(t*3)/2) }

        // Pose: braccia in avanti (flying) o aperte (crash).
        let armFwd: Float = flying ? 1.0 : 0.0
        let armSide: Float = flying ? 0.05 : 0.9

        let torso = part(R, [0, 0.45, 0], 0, 0, 0, [0.62, 0.85, 0.45])
        let chest = part(R, [0, 0.68, -0.10], 0, 0, 0, [0.70, 0.5, 0.35])
        let head  = part(R, [0, 1.28, -0.05], 0, 0, 0, [0.42, 0.42, 0.42])
        let armL  = part(R, [ 0.78, 0.85, -0.55 - 0.25*armFwd], 0, -1.35*armFwd, -armSide*0.25,
                         [0.20, 0.20, 1.05 + 0.55*armFwd])
        let armR  = part(R, [-0.78, 0.85, -0.55 - 0.25*armFwd], 0, -1.35*armFwd,  armSide*0.25,
                         [0.20, 0.20, 1.05 + 0.55*armFwd])
        let fistL = part(R, [ 0.78, 0.85, -1.85 - 1.05*armFwd], 0, 0, 0, [0.26, 0.26, 0.26])
        let fistR = part(R, [-0.78, 0.85, -1.85 - 1.05*armFwd], 0, 0, 0, [0.26, 0.26, 0.26])
        let hipL  = part(R, [ 0.30, -0.30, 0.10], 0, 0.5*(1-armFwd), 0, [0.28, 0.28, 1.15])
        let hipR  = part(R, [-0.30, -0.30, 0.10], 0, 0.5*(1-armFwd), 0, [0.28, 0.28, 1.15])
        let footL = part(R, [ 0.30, -0.32, -1.05], 0, 0, 0, [0.30, 0.18, 0.5])
        let footR = part(R, [-0.30, -0.32, -1.05], 0, 0, 0, [0.30, 0.18, 0.5])

        // Mantello: 5 segmenti, onda sinusoidale che si propaga dall'alto in basso.
        var cape: [(m: simd_float4x4, c: SIMD4<Float>)] = []
        let capeAnchor = part(R, [0, 0.9, 0.42], 0, 0, 0, [1,1,1])
        for i in 0..<5 {
            let s = Float(i)
            let wave = sin(t * 6.0 - s * 0.9) * (0.12 + 0.16 * s)
            let flare = 0.62 + 0.14 * s
            let seg = part(capeAnchor, [0, -0.55 * s - 0.25, 0.25 * s + 0.1 + wave * 0.4],
                           0, wave * 0.5, 0,
                           [flare, 0.62, 0.14 + 0.04 * s])
            cape.append((seg, SIMD4<Float>(0.78, 0.10, 0.12, 1)))
        }

        // Ombre/base
        var parts: [(m: simd_float4x4, c: SIMD4<Float>)] = [
            (torso, SIMD4<Float>(0.16, 0.24, 0.72, 1)),    // tuta blu
            (chest, SIMD4<Float>(0.85, 0.72, 0.18, 1)),    // petto dorato
            (head,  SIMD4<Float>(0.96, 0.78, 0.62, 1)),    // pelle
            (armL,  SIMD4<Float>(0.16, 0.24, 0.72, 1)),
            (armR,  SIMD4<Float>(0.16, 0.24, 0.72, 1)),
            (fistL, SIMD4<Float>(0.90, 0.75, 0.60, 1)),
            (fistR, SIMD4<Float>(0.90, 0.75, 0.60, 1)),
            (hipL,  SIMD4<Float>(0.14, 0.20, 0.62, 1)),
            (hipR,  SIMD4<Float>(0.14, 0.20, 0.62, 1)),
            (footL, SIMD4<Float>(0.80, 0.15, 0.15, 1)),    // stivali rossi
            (footR, SIMD4<Float>(0.80, 0.15, 0.15, 1)),
        ]

        // Occhi laser: quando il raggio è attivo, punto luminoso sugli occhi.
        let laserOn = fly_laser_active() == 1
        if laserOn {
            let eyeL = part(R, [ 0.12, 1.32, -0.26], 0, 0, 0, [0.09, 0.09, 0.09])
            let eyeR = part(R, [-0.12, 1.32, -0.26], 0, 0, 0, [0.09, 0.09, 0.09])
            parts.append((eyeL, SIMD4<Float>(1.0, 0.25, 0.2, 1)))
            parts.append((eyeR, SIMD4<Float>(1.0, 0.25, 0.2, 1)))
        }

        // Disegna il corpo (pipeline solida, mesh hero).
        enc.setVertexBuffer(heroVertexBuffer, offset: 0, index: 0)
        for p in parts {
            var inst = InstanceData(model: p.m, color: p.c)
            enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
            var one = Int32(1)
            enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: heroMesh.tris.count,
                                      indexType: .uint16, indexBuffer: heroIndexBuffer!,
                                      indexBufferOffset: 0, instanceCount: 1)
        }

        // Mantello e glow del boost in pipeline additiva.
        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        for c in cape {
            var inst = InstanceData(model: c.m, color: c.c)
            enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
            var one = Int32(1)
            enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: heroMesh.tris.count,
                                      indexType: .uint16, indexBuffer: heroIndexBuffer!,
                                      indexBufferOffset: 0, instanceCount: 1)
        }
        if let bg = boostGlow {
            var inst = InstanceData(model: bg.m, color: bg.c)
            enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
            var one = Int32(1)
            enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: heroMesh.tris.count,
                                      indexType: .uint16, indexBuffer: heroIndexBuffer!,
                                      indexBufferOffset: 0, instanceCount: 1)
        }
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        // Ripristina il vertex buffer a 0 (le pipeline città lo impostano da sole).
    }

    // ------------------------------------------------------------ //
    //  Anelli

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
            ptr[count] = InstanceData(model: m,
                                      color: SIMD4<Float>(0.3, 0.95, 1.0, 0.9 * pulse))
            count += 1
        }
        guard count > 0 else { return }

        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: count)
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
    }

    // ------------------------------------------------------------ //
    //  Raggi oculari: raggio primario + scie residue

    private func drawLaser(enc: MTLRenderCommandEncoder) {
        var count = 0
        var total = 0
        let active = fly_laser_active() == 1

        if active {
            var eye = FlyVec3(); var end = FlyVec3(); var heat: Float = 0
            var a: Int32 = 0
            fly_laser(&eye, &end, &a, &heat)
            let flicker = 0.85 + 0.15 * sin(uniforms.time * 90)
            let m = beamMatrix(from: SIMD3<Float>(eye.x, eye.y, eye.z),
                               to: SIMD3<Float>(end.x, end.y, end.z),
                               width: 0.30 + 0.25 * heat)
            let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: 2)
            let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)
            ptr[0] = InstanceData(model: m, color: SIMD4<Float>(1.0, 0.15, 0.1, 0.95 * flicker))
            // alone esterno
            let m2 = beamMatrix(from: SIMD3<Float>(eye.x, eye.y, eye.z),
                                to: SIMD3<Float>(end.x, end.y, end.z),
                                width: 0.7 + 0.4 * heat)
            ptr[1] = InstanceData(model: m2, color: SIMD4<Float>(1.0, 0.4, 0.3, 0.35 * flicker))
            count = 2
            total = 2
        }

        // Scie residue.
        let segs = Int(fly_laser_seg_count())
        if segs > 0 {
            let need = total + segs
            let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: need)
            let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)
            for i in 0..<segs {
                var a = FlyVec3(); var b = FlyVec3(); var w: Float = 0; var life: Float = 0
                fly_laser_seg(Int32(i), &a, &b, &w, &life)
                let m = beamMatrix(from: SIMD3<Float>(a.x, a.y, a.z),
                                   to: SIMD3<Float>(b.x, b.y, b.z), width: w * life)
                ptr[total + i] = InstanceData(model: m,
                                              color: SIMD4<Float>(1.0, 0.2, 0.12, 0.35 * life))
            }
            count += segs
        }
        guard count > 0 else { return }

        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(glowInstances, offset: 0, index: 2)
        var c = Int32(count)
        enc.setVertexBytes(&c, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: count)
        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
    }

    /// Matrice di un raggio orientato da `from` a `to` (cubo allungato lungo Z).
    private func beamMatrix(from: SIMD3<Float>, to: SIMD3<Float>, width: Float) -> simd_float4x4 {
        let dir = to - from
        let len = max(0.1, simd_length(dir))
        let d = dir / len
        // Il forward del cubo è -Z: allineo -Z con d.
        let w = simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0))
        var q = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        if abs(simd_dot(d, SIMD3<Float>(0, 0, -1))) < 0.999 {
            q = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: d)
        } else {
            q = w
        }
        let mid = (from + to) * 0.5
        return MathUtil.translate(x: mid.x, y: mid.y, z: mid.z)
            * simd_float4x4(q)
            * MathUtil.scaleNonUniform(sx: width, sy: width, sz: len * 0.5)
    }

    // ------------------------------------------------------------ //
    //  Particelle

    private func drawParticles(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_particle_count())
        guard n > 0 else { return }
        let buf = ensure(&glowInstances, capacity: &glowCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity)

        for i in 0..<n {
            var pos = FlyVec3(); var size: Float = 0; var life: Float = 0; var hue: Float = 0
            fly_particle(Int32(i), &pos, &size, &life, &hue)
            let m = MathUtil.translate(x: pos.x, y: pos.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size, sy: size, sz: size)
            let c: SIMD4<Float> = hue < 0.05
                ? SIMD4<Float>(1.0, 0.35, 0.1, life * 0.9)       // laser/esplosioni
                : SIMD4<Float>(1.0, 0.75, 0.3, life * 0.85)      // boost/anelli
            ptr[i] = InstanceData(model: m, color: c)
        }

        enc.setRenderPipelineState(pipelineGlow)
        enc.setDepthStencilState(noDepthState)
        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var count = Int32(n)
        enc.setVertexBytes(&count, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: n)
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

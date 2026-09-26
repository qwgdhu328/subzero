// Renderer.swift — rendering 3D con Metal: edifici, anelli, particelle, cielo.

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
        d2setup(d, view: view, additive: false)
        pipelineCity = try! device.makeRenderPipelineState(descriptor: d)

        let d2 = MTLRenderPipelineDescriptor()
        d2.vertexFunction = vsFn
        d2.fragmentFunction = glowFn
        d2.colorAttachments[0].pixelFormat = view.colorPixelFormat
        d2.colorAttachments[0].isBlendingEnabled = true
        d2setup(d2, view: view, additive: true)
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

    private func d2setup(_ d: MTLRenderPipelineDescriptor, view: MTKView, additive: Bool) {
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
        d.depthAttachmentPixelFormat = view.depthStencilPixelFormat
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // 1) motore C++: update a timestep fisso
        fly_update(1.0 / Double(view.preferredFramesPerSecond),
                   Int32(view.drawableSize.width),
                   Int32(view.drawableSize.height))

        // punteggio best per il restart
        bestScore = max(bestScore, fly_best())

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        let aspect = Float(view.drawableSize.width / max(1.0, view.drawableSize.height))
        uniforms = makeUniforms(aspect: aspect)

        // Cielo: clear color tramonto
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.45, green: 0.62, blue: 0.85, alpha: 1)

        enc.setRenderPipelineState(pipelineCity)
        enc.setDepthStencilState(depthState)
        enc.setCullMode(.none)
        enc.setVertexBuffer(uniformBuffer(), offset: 0, index: 1)

        drawCity(enc: enc)
        drawPlayer(enc: enc)
        drawRings(enc: enc)
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
    //  Edifici

    private func drawCity(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_building_count())
        guard n > 0 else { return }
        let buf = ensure(&solidInstances, capacity: &solidCapacity, needed: n)
        let ptr = buf.contents().bindMemory(to: InstanceData.self, capacity: solidCapacity)

        for i in 0..<n {
            var pos = FlyVec3(); var size = FlyVec3(); var hue: Float = 0
            fly_building(Int32(i), &pos, &size, &hue)
            let m = MathUtil.translate(x: pos.x, y: pos.y + size.y, z: pos.z)
                * MathUtil.scaleNonUniform(sx: size.x, sy: size.y, sz: size.z)
            ptr[i] = InstanceData(model: m, color: windowColor(hue: hue, height: size.y))
        }

        enc.setVertexBuffer(buf, offset: 0, index: 2)
        var count = Int32(n)
        enc.setVertexBytes(&count, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: n)
    }

    private func windowColor(hue: Float, height: Float) -> SIMD4<Float> {
        let warm = SIMD4<Float>(0.98, 0.72, 0.35, 1)
        let cool = SIMD4<Float>(0.55, 0.78, 1.0, 1)
        let t = sin(hue * 43.7) * 0.5 + 0.5
        let win = warm * t + cool * (1 - t)
        let body = SIMD4<Float>(0.07, 0.08, 0.12, 1)
        let lum = min(1, height / 160)
        return SIMD4<Float>(body.x * (1-lum) + win.x * lum * 0.35,
                            body.y * (1-lum) + win.y * lum * 0.35,
                            body.z * (1-lum) + win.z * lum * 0.35, 1)
    }

    // ------------------------------------------------------------ //
    //  Anelli

    private func drawRings(enc: MTLRenderCommandEncoder) {
        let n = Int(fly_ring_count())
        guard n > 0 else { return }
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
            writeGlow(ptr: glowInstances!.contents().bindMemory(to: InstanceData.self, capacity: glowCapacity),
                      index: count, model: m,
                      color: SIMD4<Float>(0.3, 0.95, 1.0, 0.9 * pulse))
            count += 1
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

    private func writeGlow(ptr: UnsafeMutablePointer<InstanceData>, index: Int,
                           model: simd_float4x4, color: SIMD4<Float>) {
        ptr[index] = InstanceData(model: model, color: color)
    }

    // ------------------------------------------------------------ //
    //  Giocatore (capsula stilizzata = cubo scalato)

    private func drawPlayer(enc: MTLRenderCommandEncoder) {
        let pos = fly_player_pos()
        let q = fly_player_quat()
        let qw = sqrtf(max(0, 1 - q.x*q.x - q.y*q.y - q.z*q.z))
        let m = MathUtil.translate(x: pos.x, y: pos.y + 1.2, z: pos.z)
            * MathUtil.rotateQuat(x: q.x, y: q.y, z: q.z, w: qw)
            * MathUtil.scaleNonUniform(sx: 0.9, sy: 0.55, sz: 2.2)

        var inst = InstanceData(model: m, color: SIMD4<Float>(0.95, 0.32, 0.25, 1))
        enc.setVertexBytes(&inst, length: MemoryLayout<InstanceData>.stride, index: 2)
        var one = Int32(1)
        enc.setVertexBytes(&one, length: MemoryLayout<Int32>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36,
                           instanceCount: 1)
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
            ptr[i] = InstanceData(model: m,
                                  color: SIMD4<Float>(1.0, 0.75, 0.3, life * 0.85))
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

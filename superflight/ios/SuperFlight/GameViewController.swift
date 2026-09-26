import UIKit
import Metal
import MetalKit

// GameViewController — crea il renderer Metal e pilota il motore C++.
class GameViewController: UIViewController {

    private var renderer: Renderer!
    private var mtkView: MTKView!
    private var hud: HUDView!

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal non disponibile su questo dispositivo")
        }

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.framebufferOnly = true
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 120
        view.addSubview(mtkView)

        renderer = Renderer(metalKitView: mtkView)

        hud = HUDView(frame: view.bounds)
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hud.onRestart = { [weak self] in fly_reset(self?.renderer.bestScore ?? 0) }
        view.addSubview(hud)

        // Motore C++
        fly_create()
        fly_reset(0)

        // Input: virtual joystick dinamico (tocco anywhere = centro stick)
        let touch = TouchController(sceneView: mtkView)
        touch.onStick = { [weak self] pitch, yaw, roll in
            fly_set_stick(pitch, yaw, roll)
        }
        touch.onBoost = { [weak self] on in
            fly_set_boost(on ? 1 : 0)
        }
        mtkView.isUserInteractionEnabled = true
        touch.attach(to: mtkView)
        renderer.touch = touch
        hud.touch = touch

        mtkView.delegate = renderer
    }
}

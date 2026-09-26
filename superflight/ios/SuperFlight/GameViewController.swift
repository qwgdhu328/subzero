import UIKit
import MetalKit

// GameView — MTKView che inoltra i touch al controller.
final class GameView: MTKView {
    weak var touchDelegate: TouchController?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        touchDelegate?.touchesBegan(touches, in: self)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        touchDelegate?.touchesMoved(touches, in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        touchDelegate?.touchesEnded(touches, in: self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        touchDelegate?.touchesCancelled(touches, in: self)
    }
}

// GameViewController — crea il renderer Metal e pilota il motore C++.
final class GameViewController: UIViewController {

    private var renderer: Renderer!
    private var gameView: GameView!
    private var hud: HUDView!
    private let touch = TouchController()

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal non disponibile su questo dispositivo")
        }

        gameView = GameView(frame: view.bounds, device: device)
        gameView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        gameView.framebufferOnly = true
        gameView.depthStencilPixelFormat = .depth32Float
        gameView.colorPixelFormat = .bgra8Unorm
        gameView.preferredFramesPerSecond = 120
        gameView.isUserInteractionEnabled = true
        gameView.touchDelegate = touch
        view.addSubview(gameView)

        renderer = Renderer(metalKitView: gameView)
        gameView.delegate = renderer

        hud = HUDView(frame: view.bounds)
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        hud.onRestart = { [weak self] in
            fly_reset(Int32(self?.renderer.bestScore ?? 0))
        }
        view.addSubview(hud)

        // Motore C++
        fly_create()
        fly_reset(0)

        // Input → motore
        touch.onStick = { pitch, yaw, roll in
            fly_set_stick(pitch, yaw, roll)
        }
        touch.onBoost = { on in
            fly_set_boost(on ? 1 : 0)
        }
    }
}

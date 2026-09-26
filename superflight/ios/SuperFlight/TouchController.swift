// TouchController — joystick virtuale dinamico.
// Il primo dito pilota: su/giù = pitch (quota), destra/sinistra = yaw (svolta).
// Il secondo dito in qualsiasi punto = BOOST.
// L'input è normalizzato -1..1 sul raggio di 130pt.

import UIKit

final class TouchController: NSObject {
    var onStick: ((Float, Float, Float) -> Void)?
    var onBoost: ((Bool) -> Void)?

    private weak var view: UIView?
    private var center: CGPoint = .zero
    private var stickTouch: UITouch?
    private var boostTouch: UITouch?
    private let radius: CGFloat = 130

    init(sceneView: UIView) {
        self.view = sceneView
        super.init()
    }

    // ------------------------------------------------------------ //

    private func stickValue(_ location: CGPoint) -> (Float, Float) {
        let dx = (location.x - center.x) / radius
        let dy = (location.y - center.y) / radius
        let yaw = Float(max(-1, min(1, dx)))
        let pitch = Float(max(-1, min(1, -dy)))   // su = salita
        return (pitch, yaw)
    }

    private func updateStick() {
        guard let t = stickTouch, let v = view else { return }
        let (pitch, yaw) = stickValue(t.location(in: v))
        onStick?(pitch, yaw, 0)
    }

    // ------------------------------------------------------------ //
    //  Eventi inoltrati dal delegate della view (GameView)

    func touchesBegan(_ touches: Set<UITouch>, in host: UIView) {
        for t in touches {
            if stickTouch == nil {
                stickTouch = t
                center = t.location(in: host)
                onStick?(0, 0, 0)
            } else if boostTouch == nil {
                boostTouch = t
                onBoost?(true)
            }
        }
    }

    func touchesMoved(_ touches: Set<UITouch>, in host: UIView) {
        updateStick()
    }

    func touchesEnded(_ touches: Set<UITouch>, in host: UIView) {
        for t in touches {
            if t === boostTouch {
                boostTouch = nil
                onBoost?(false)
            } else if t === stickTouch {
                stickTouch = nil
                onStick?(0, 0, 0)
            }
        }
    }

    func touchesCancelled(_ touches: Set<UITouch>, in host: UIView) {
        touchesEnded(touches, in: host)
    }
}

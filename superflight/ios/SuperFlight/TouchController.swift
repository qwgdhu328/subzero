// TouchController — joystick virtuale dinamico.
// Il primo tocco definisce il centro; muovendo il dito si pilota:
//   • su/giù      → pitch (salita/discesa)
//   • destra/sinistra → yaw (svolta)
//   • doppio tocco con secondo dito (o secondo dito tenuto) → boost
// L'input è normalizzato -1..1 sul raggio di 130pt.

import UIKit

final class TouchController: NSObject {
    var onStick: ((Float, Float, Float) -> Void)?
    var onBoost: ((Bool) -> Void)?

    private weak var view: UIView?
    private var center: CGPoint = .zero
    private var active = false
    private var boostTouch: UITouch?
    private let radius: CGFloat = 130

    init(sceneView: UIView) {
        self.view = sceneView
    }

    func attach(to view: UIView) {
        let g = GestureTarget(controller: self)
        view.addGestureRecognizer(UITapGestureRecognizer(target: g, action: #selector(GestureTarget.tap(_:))))
        // Il lavoro vero avviene nelle override dei touch (tramite ViewSubclass)
        view.isUserInteractionEnabled = true
    }

    func begin(_ location: CGPoint) {
        center = location
        active = true
    }

    func moved(_ location: CGPoint) {
        guard active else { return }
        let dx = (location.x - center.x) / radius
        let dy = (location.y - center.y) / radius
        let yaw = Float(max(-1, min(1, dx)))
        let pitch = Float(max(-1, min(1, -dy)))   // su = salita
        onStick?(pitch, yaw, 0)
    }

    func end() {
        active = false
        onStick?(0, 0, 0)
    }

    // Gestione del boost con secondo dito
    func touchesBegan(_ touches: Set<UITouch>, in view: UIView) {
        if active {
            if boostTouch == nil {
                boostTouch = touches.first
                onBoost?(true)
            }
        } else if let t = touches.first {
            begin(t.location(in: view))
        }
    }

    func touchesMoved(_ touches: Set<UITouch>, in view: UIView) {
        if let t = touches.first, t !== boostTouch {
            moved(t.location(in: view))
        }
    }

    func touchesEnded(_ touches: Set<UITouch>) {
        if let t = boostTouch, touches.contains(t) {
            boostTouch = nil
            onBoost?(false)
        }
        if touches.count >= 1 && boostTouch == nil {
            end()
        }
    }
}

// Handler dei tap per il menu / restart
final class GestureTarget: NSObject {
    weak var controller: TouchController?
    init(controller: TouchController) { self.controller = controller }
    @objc func tap(_ g: UITapGestureRecognizer) {
        controller?.begin(g.location(in: g.view))
    }
}

// GameSettings — impostazioni persistite (UserDefaults): grafica, sensibilità, FPS.

import Foundation

enum GraphicsQuality: Int, CaseIterable {
    case alta = 0    // tutto: 40 NPC, nuvole, particelle complete
    case media = 1   // 20 NPC, metà nuvole, metà particelle
    case lite = 2    // 8 NPC, niente nuvole, un quarto delle particelle
    case ultra = 3   // 4K Ultra: HDR+MSAA+bloom, 60 NPC, 900 particelle, 32 nuvole

    var label: String {
        switch self {
        case .alta: return "Alta"
        case .media: return "Media"
        case .lite: return "Lite"
        case .ultra: return "Ultra 4K"
        }
    }
    var npcLimit: Int32 {
        switch self {
        case .alta: return 40
        case .media: return 20
        case .lite: return 8
        case .ultra: return 60
        }
    }
    var particleLimit: Int32 {
        switch self {
        case .alta: return 600
        case .media: return 300
        case .lite: return 120
        case .ultra: return 900
        }
    }
    // Risoluzione di rendering relativa allo schermo (1.0 = nativa del device,
    // tipicamente 3x su iPhone → ~4K su schermi ProMotion). Ultra renderizza alla
    // scala nativa massima con pipeline HDR+MSAA.
    var renderScale: CGFloat {
        switch self {
        case .ultra: return 1.0
        case .alta: return 1.0
        case .media: return 0.75
        case .lite: return 0.5
        }
    }
    // Nuvole disegnate (il motore grafico genera 32 istanze totali).
    var cloudCount: Int {
        switch self {
        case .ultra: return 32
        case .alta: return 22
        case .media: return 11
        case .lite: return 0
        }
    }
}

final class GameSettings {
    static let shared = GameSettings()

    var quality: GraphicsQuality
    var sensitivity: Float        // 0.6 (bassa) · 1.0 (normale) · 1.5 (alta)
    var fps60: Bool               // false = 120 fps

    private let kQuality = "sf.quality"
    private let kSens = "sf.sensitivity"
    private let kFps60 = "sf.fps60"

    private init() {
        let d = UserDefaults.standard
        quality = GraphicsQuality(rawValue: d.integer(forKey: kQuality)) ?? .alta
        let s = d.object(forKey: kSens) as? Float ?? 1.0
        sensitivity = max(0.5, min(1.6, s))
        fps60 = d.bool(forKey: kFps60) && d.object(forKey: kFps60) != nil
            ? d.bool(forKey: kFps60)
            : false
    }

    func save() {
        let d = UserDefaults.standard
        d.set(quality.rawValue, forKey: kQuality)
        d.set(sensitivity, forKey: kSens)
        d.set(fps60, forKey: kFps60)
    }

    func applyLimits() {
        fly_set_limits(quality.npcLimit, quality.particleLimit)
    }
}

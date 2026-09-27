// HUDView — interfaccia: menu AVVIA PARTITA, punteggio, tasti salto/volo/laser.
// touchesBegan restituisce nil → i tocchi passano attraverso alla GameView,
// così il joystick dinamico continua a funzionare in tutto lo schermo;
// solo i pulsanti catturano i tocchi su di essi.

import UIKit

final class HUDView: UIView {
    var onRestart: (() -> Void)?       // "AVVIA PARTITA"
    var onJump: (() -> Void)?
    var onFlyToggle: (() -> Void)?
    var onLaser: ((Bool) -> Void)?
    weak var touch: TouchController?

    private let scoreLabel = UILabel()
    private let bestLabel = UILabel()
    private let speedLabel = UILabel()
    private let altLabel = UILabel()
    private let modeLabel = UILabel()
    private let boostBar = UIView()
    private let boostTrack = UIView()
    private let menuPanel = UIView()
    private let menuTitle = UILabel()
    private let menuSubtitle = UILabel()
    private let finalScore = UILabel()
    private let playButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let jumpButton = UIButton(type: .system)
    private let flyButton = UIButton(type: .system)
    private let laserButton = UIButton(type: .system)
    private let heatTrack = UIView()
    private let heatBar = UIView()

    // Settings
    private let gearButton = UIButton(type: .system)
    private let settingsPanel = UIView()
    private let settingsTitle = UILabel()
    private let qualityLabel = UILabel()
    private let qualitySegmented = UISegmentedControl(items: ["Alta", "Media", "Lite", "Ultra 4K"])
    private let sensLabel = UILabel()
    private let sensSegmented = UISegmentedControl(items: ["Bassa", "Normale", "Alta"])
    private let fpsLabel = UILabel()
    private let fpsSegmented = UISegmentedControl(items: ["60 FPS", "120 FPS"])
    private let settingsClose = UIButton(type: .system)
    var onSettingsChanged: (() -> Void)?
    private var settingsOpen = false

    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear

        setupLabels()
        setupBoostBar()
        setupControls()
        setupMenu()
        setupSettings()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    // I tocchi fuori dai pulsanti attraversano la HUD (joystick dinamico).
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let v = super.hitTest(point, with: event)
        return v === self ? nil : v
    }

    private func setupLabels() {
        let big = UIFont.monospacedDigitSystemFont(ofSize: 40, weight: .heavy)
        for l in [scoreLabel, bestLabel, speedLabel, altLabel, modeLabel] {
            l.textColor = .white
            l.textAlignment = .center
            l.layer.shadowColor = UIColor.black.cgColor
            l.layer.shadowOpacity = 0.7
            l.layer.shadowRadius = 3
            l.layer.shadowOffset = .zero
            addSubview(l)
        }
        scoreLabel.font = big
        bestLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        bestLabel.textColor = UIColor(white: 1, alpha: 0.75)
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        speedLabel.textColor = UIColor(white: 1, alpha: 0.8)
        altLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        altLabel.textColor = UIColor(white: 1, alpha: 0.8)
        modeLabel.font = .systemFont(ofSize: 13, weight: .bold)
        modeLabel.textColor = UIColor(red: 0.65, green: 0.85, blue: 1, alpha: 0.95)

        hintLabel.text = "Trascina per muoverti  ·  2° dito = corri/volami veloce"
        hintLabel.textColor = UIColor(white: 1, alpha: 0.65)
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textAlignment = .center
        addSubview(hintLabel)
    }

    private func setupBoostBar() {
        boostTrack.backgroundColor = UIColor(white: 1, alpha: 0.15)
        boostTrack.layer.cornerRadius = 4
        boostTrack.layer.cornerCurve = .continuous
        boostBar.backgroundColor = UIColor(red: 1, green: 0.75, blue: 0.2, alpha: 1)
        boostBar.layer.cornerRadius = 4
        boostBar.layer.cornerCurve = .continuous
        addSubview(boostTrack)
        boostTrack.addSubview(boostBar)
    }

    private func makeActionButton(_ title: String, _ bg: UIColor, _ border: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .heavy)
        b.tintColor = .white
        b.backgroundColor = bg
        b.layer.cornerRadius = 34
        b.layer.cornerCurve = .continuous
        b.layer.borderWidth = 2
        b.layer.borderColor = border.cgColor
        b.isExclusiveTouch = true
        return b
    }

    private func setupControls() {
        jumpButton.setTitle("SALTO", for: .normal)
        jumpButton.backgroundColor = UIColor(red: 0.2, green: 0.45, blue: 0.95, alpha: 0.42)
        jumpButton.layer.borderColor = UIColor(red: 0.4, green: 0.65, blue: 1, alpha: 0.9).cgColor
        jumpButton.addTarget(self, action: #selector(jumpTapped), for: .touchUpInside)
        addSubview(jumpButton)

        flyButton.setTitle("VOLO", for: .normal)
        flyButton.backgroundColor = UIColor(red: 0.95, green: 0.75, blue: 0.15, alpha: 0.42)
        flyButton.layer.borderColor = UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 0.9).cgColor
        flyButton.addTarget(self, action: #selector(flyTapped), for: .touchUpInside)
        addSubview(flyButton)

        laserButton.setTitle("👁", for: .normal)
        laserButton.titleLabel?.font = .systemFont(ofSize: 26)
        laserButton.backgroundColor = UIColor(white: 0, alpha: 0.35)
        laserButton.layer.borderColor = UIColor(red: 1, green: 0.35, blue: 0.3, alpha: 0.9).cgColor
        laserButton.addTarget(self, action: #selector(laserDown), for: .touchDown)
        laserButton.addTarget(self, action: #selector(laserUp),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])
        addSubview(laserButton)

        heatTrack.backgroundColor = UIColor(white: 1, alpha: 0.15)
        heatTrack.layer.cornerRadius = 3
        heatTrack.layer.cornerCurve = .continuous
        heatBar.backgroundColor = UIColor(red: 1, green: 0.3, blue: 0.25, alpha: 1)
        heatBar.layer.cornerRadius = 3
        heatBar.layer.cornerCurve = .continuous
        addSubview(heatTrack)
        heatTrack.addSubview(heatBar)
    }

    private func setupMenu() {
        menuPanel.backgroundColor = UIColor(white: 0.04, alpha: 0.78)
        menuPanel.layer.cornerRadius = 28
        menuPanel.layer.cornerCurve = .continuous
        menuPanel.isHidden = false
        addSubview(menuPanel)

        menuTitle.text = "🦸 SUPERMAN"
        menuTitle.font = .systemFont(ofSize: 36, weight: .black)
        menuTitle.textColor = .white
        menuTitle.textAlignment = .center
        menuPanel.addSubview(menuTitle)

        menuSubtitle.text = "Città di Metropolis — cammina, salta, vola"
        menuSubtitle.font = .systemFont(ofSize: 14, weight: .medium)
        menuSubtitle.textColor = UIColor(white: 1, alpha: 0.65)
        menuSubtitle.textAlignment = .center
        menuPanel.addSubview(menuSubtitle)

        finalScore.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        finalScore.textColor = UIColor(white: 1, alpha: 0.85)
        finalScore.textAlignment = .center
        menuPanel.addSubview(finalScore)

        playButton.setTitle("  ▶  AVVIA PARTITA  ", for: .normal)
        playButton.titleLabel?.font = .systemFont(ofSize: 20, weight: .bold)
        playButton.setTitleColor(.black, for: .normal)
        playButton.backgroundColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        playButton.layer.cornerRadius = 24
        playButton.layer.cornerCurve = .continuous
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        menuPanel.addSubview(playButton)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scoreLabel.frame = CGRect(x: 0, y: bounds.height * 0.06, width: bounds.width, height: 50)
        bestLabel.frame = CGRect(x: 0, y: scoreLabel.frame.maxY + 2, width: bounds.width, height: 20)
        modeLabel.frame = CGRect(x: 0, y: bestLabel.frame.maxY + 2, width: bounds.width, height: 18)
        speedLabel.frame = CGRect(x: 16, y: bounds.height - 34, width: 180, height: 20)
        altLabel.frame = CGRect(x: bounds.width - 196, y: bounds.height - 34, width: 180, height: 20)
        boostTrack.frame = CGRect(x: bounds.width/2 - 90, y: bounds.height - 30, width: 180, height: 9)
        boostBar.frame = boostTrack.bounds.insetBy(dx: 0, dy: 0)
        hintLabel.frame = CGRect(x: 0, y: bounds.height * 0.16, width: bounds.width, height: 20)

        // Tasti azione: a destra, impilati.
        laserButton.frame = CGRect(x: bounds.width - 88, y: bounds.height - 88, width: 64, height: 64)
        flyButton.frame  = CGRect(x: bounds.width - 96, y: bounds.height - 172, width: 80, height: 68)
        jumpButton.frame = CGRect(x: bounds.width - 96, y: bounds.height - 256, width: 80, height: 68)
        heatTrack.frame = CGRect(x: laserButton.frame.minX + 4, y: laserButton.frame.minY - 12,
                                 width: 56, height: 6)
        heatBar.frame = heatTrack.bounds

        let pw: CGFloat = min(380, bounds.width * 0.86)
        let ph: CGFloat = 280
        menuPanel.frame = CGRect(x: (bounds.width - pw)/2, y: (bounds.height - ph)/2, width: pw, height: ph)
        menuTitle.frame = CGRect(x: 0, y: 30, width: pw, height: 44)
        menuSubtitle.frame = CGRect(x: 0, y: 76, width: pw, height: 20)
        finalScore.frame = CGRect(x: 0, y: 104, width: pw, height: 24)
        playButton.frame = CGRect(x: (pw - 220)/2, y: 152, width: 220, height: 56)
        gearButton.frame = CGRect(x: bounds.width - 56, y: 16, width: 44, height: 44)

        // Pannello settings
        let sw: CGFloat = min(360, bounds.width * 0.9)
        let sh: CGFloat = 330
        settingsPanel.frame = CGRect(x: (bounds.width - sw)/2, y: (bounds.height - sh)/2, width: sw, height: sh)
        settingsTitle.frame = CGRect(x: 0, y: 22, width: sw, height: 30)
        qualityLabel.frame = CGRect(x: 20, y: 68, width: sw - 40, height: 20)
        qualitySegmented.frame = CGRect(x: 20, y: 92, width: sw - 40, height: 32)
        sensLabel.frame = CGRect(x: 20, y: 140, width: sw - 40, height: 20)
        sensSegmented.frame = CGRect(x: 20, y: 164, width: sw - 40, height: 32)
        fpsLabel.frame = CGRect(x: 20, y: 212, width: sw - 40, height: 20)
        fpsSegmented.frame = CGRect(x: 20, y: 236, width: sw - 40, height: 32)
        settingsClose.frame = CGRect(x: (sw - 160)/2, y: 276, width: 160, height: 40)
    }

    @objc private func playTapped() {
        onRestart?()
        menuPanel.isHidden = true
    }

    // ------------------------------------------------------------ //
    //  Settings

    private func setupSettings() {
        gearButton.setTitle("⚙", for: .normal)
        gearButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
        gearButton.tintColor = .white
        gearButton.backgroundColor = UIColor(white: 0, alpha: 0.35)
        gearButton.layer.cornerRadius = 22
        gearButton.layer.cornerCurve = .continuous
        gearButton.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        addSubview(gearButton)

        settingsPanel.backgroundColor = UIColor(white: 0.04, alpha: 0.9)
        settingsPanel.layer.cornerRadius = 24
        settingsPanel.layer.cornerCurve = .continuous
        settingsPanel.isHidden = true
        addSubview(settingsPanel)

        settingsTitle.text = "IMPOSTAZIONI"
        settingsTitle.font = .systemFont(ofSize: 22, weight: .black)
        settingsTitle.textColor = .white
        settingsTitle.textAlignment = .center
        settingsPanel.addSubview(settingsTitle)

        for l in [qualityLabel, sensLabel, fpsLabel] {
            l.font = .systemFont(ofSize: 14, weight: .semibold)
            l.textColor = UIColor(white: 1, alpha: 0.85)
            settingsPanel.addSubview(l)
        }
        qualityLabel.text = "Grafica"
        sensLabel.text = "Sensibilità joystick"
        fpsLabel.text = "Frequenza"

        qualitySegmented.selectedSegmentIndex = GameSettings.shared.quality.rawValue
        qualitySegmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        qualitySegmented.addTarget(self, action: #selector(qualityChanged), for: .valueChanged)
        settingsPanel.addSubview(qualitySegmented)

        let sensIndex = GameSettings.shared.sensitivity < 0.85 ? 0 : (GameSettings.shared.sensitivity > 1.15 ? 2 : 1)
        sensSegmented.selectedSegmentIndex = sensIndex
        sensSegmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        sensSegmented.addTarget(self, action: #selector(sensChanged), for: .valueChanged)
        settingsPanel.addSubview(sensSegmented)

        fpsSegmented.selectedSegmentIndex = GameSettings.shared.fps60 ? 0 : 1
        fpsSegmented.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        fpsSegmented.addTarget(self, action: #selector(fpsChanged), for: .valueChanged)
        settingsPanel.addSubview(fpsSegmented)

        settingsClose.setTitle("  ✕ CHIUDI  ", for: .normal)
        settingsClose.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        settingsClose.setTitleColor(.black, for: .normal)
        settingsClose.backgroundColor = UIColor(red: 1, green: 0.8, blue: 0.2, alpha: 1)
        settingsClose.layer.cornerRadius = 18
        settingsClose.layer.cornerCurve = .continuous
        settingsClose.addTarget(self, action: #selector(closeSettings), for: .touchUpInside)
        settingsPanel.addSubview(settingsClose)
    }

    @objc private func gearTapped() {
        settingsOpen.toggle()
        settingsPanel.isHidden = !settingsOpen
    }

    @objc private func qualityChanged() {
        GameSettings.shared.quality = GraphicsQuality(rawValue: qualitySegmented.selectedSegmentIndex) ?? .alta
        GameSettings.shared.save()
        onSettingsChanged?()
    }

    @objc private func sensChanged() {
        GameSettings.shared.sensitivity = [0.7, 1.0, 1.4][sensSegmented.selectedSegmentIndex]
        GameSettings.shared.save()
        onSettingsChanged?()
    }

    @objc private func fpsChanged() {
        GameSettings.shared.fps60 = fpsSegmented.selectedSegmentIndex == 0
        GameSettings.shared.save()
        onSettingsChanged?()
    }

    @objc private func closeSettings() {
        settingsOpen = false
        settingsPanel.isHidden = true
    }

    @objc private func jumpTapped() { onJump?() }
    @objc private func flyTapped()  { onFlyToggle?() }
    @objc private func laserDown()  { onLaser?(true) }
    @objc private func laserUp()    { onLaser?(false) }

    @objc private func tick() {
        let state = fly_state()
        scoreLabel.text = "\(fly_score())"
        bestLabel.text = "BEST \(fly_best())   ·   anelli \(fly_rings())"
        speedLabel.text = String(format: "%.0f km/h", fly_speed() * 3.6)
        altLabel.text = String(format: "%.0f m", fly_altitude())
        boostBar.frame.size.width = boostTrack.bounds.width * CGFloat(fly_boost())

        switch state {
        case 1: modeLabel.text = "✈ IN VOLO — premi VOLO per atterrare"
        case 3: modeLabel.text = "🚶 A PIEDI — SALTO ×2 per volare"
        case 2: modeLabel.text = "💥 CRASH!"
        default: modeLabel.text = ""
        }

        let heat = CGFloat(fly_laser_heat())
        heatBar.frame.size.width = heatTrack.bounds.width * heat
        heatBar.backgroundColor = heat >= 0.85
            ? UIColor(red: 0.55, green: 0.05, blue: 0.05, alpha: 1)
            : UIColor(red: 1, green: 0.3 - 0.15 * heat, blue: 0.25, alpha: 1)

        let inMenu = (state == 0)
        menuPanel.isHidden = !inMenu || settingsOpen
        gearButton.isHidden = settingsOpen || state == 2
        settingsPanel.isHidden = !settingsOpen
        if state == 2 || (inMenu && fly_time() > 0.5) {
            finalScore.text = "Punteggio: \(fly_score())  ·  Anelli: \(fly_rings())"
        } else {
            finalScore.text = "Esplora la città, distruggi coi laser, passa gli anelli"
        }
        hintLabel.isHidden = inMenu || fly_time() > 8.0

        // Nascondi i tasti di gioco quando si è nel menu.
        for v in [jumpButton, flyButton, laserButton, heatTrack] { v.isHidden = inMenu }
    }
}

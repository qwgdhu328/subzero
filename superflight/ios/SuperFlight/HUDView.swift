// HUDView — interfaccia sopra il gioco: punteggio, velocità, boost, menu.
// UIKit puro per zero overhead sul render thread.

import UIKit

final class HUDView: UIView {
    var onRestart: (() -> Void)?
    weak var touch: TouchController?

    private let scoreLabel = UILabel()
    private let bestLabel = UILabel()
    private let speedLabel = UILabel()
    private let altLabel = UILabel()
    private let boostBar = UIView()
    private let boostTrack = UIView()
    private let menuPanel = UIView()
    private let menuTitle = UILabel()
    private let finalScore = UILabel()
    private let playButton = UIButton(type: .system)
    private let hintLabel = UILabel()
    private let laserButton = UIButton(type: .system)
    private let heatTrack = UIView()
    private let heatBar = UIView()
    var onLaser: ((Bool) -> Void)?

    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear

        setupLabels()
        setupBoostBar()
        setupLaserControls()
        setupMenu()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) non supportato") }

    private func setupLabels() {
        let big = UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .heavy)
        for l in [scoreLabel, bestLabel, speedLabel, altLabel] {
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

        hintLabel.text = "Trascina per volare  ·  secondo dito = BOOST  ·  👁 = raggi oculari"
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

    private func setupLaserControls() {
        laserButton.setTitle("👁", for: .normal)
        laserButton.titleLabel?.font = .systemFont(ofSize: 26)
        laserButton.tintColor = .white
        laserButton.backgroundColor = UIColor(white: 0, alpha: 0.35)
        laserButton.layer.cornerRadius = 32
        laserButton.layer.cornerCurve = .continuous
        laserButton.layer.borderWidth = 2
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

    @objc private func laserDown() { onLaser?(true) }
    @objc private func laserUp()   { onLaser?(false) }

    private func setupMenu() {
        menuPanel.backgroundColor = UIColor(white: 0.05, alpha: 0.72)
        menuPanel.layer.cornerRadius = 28
        menuPanel.layer.cornerCurve = .continuous
        menuPanel.isHidden = false
        addSubview(menuPanel)

        menuTitle.text = "🦸 SUPERMAN"
        menuTitle.font = .systemFont(ofSize: 34, weight: .black)
        menuTitle.textColor = .white
        menuTitle.textAlignment = .center
        menuPanel.addSubview(menuTitle)

        finalScore.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        finalScore.textColor = UIColor(white: 1, alpha: 0.85)
        finalScore.textAlignment = .center
        menuPanel.addSubview(finalScore)

        playButton.setTitle("  ✈  VOLA  ", for: .normal)
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
        scoreLabel.frame = CGRect(x: 0, y: bounds.height * 0.06, width: bounds.width, height: 54)
        bestLabel.frame = CGRect(x: 0, y: scoreLabel.frame.maxY + 2, width: bounds.width, height: 20)
        speedLabel.frame = CGRect(x: 16, y: bounds.height - 34, width: 180, height: 20)
        altLabel.frame = CGRect(x: bounds.width - 196, y: bounds.height - 34, width: 180, height: 20)
        boostTrack.frame = CGRect(x: bounds.width/2 - 90, y: bounds.height - 30, width: 180, height: 9)
        boostBar.frame = boostTrack.bounds.insetBy(dx: 0, dy: 0)
        heatTrack.frame = CGRect(x: bounds.width/2 - 70, y: bounds.height - 48, width: 140, height: 6)
        heatBar.frame = heatTrack.bounds
        laserButton.frame = CGRect(x: bounds.width - 88, y: bounds.height - 128, width: 64, height: 64)
        hintLabel.frame = CGRect(x: 0, y: bounds.height * 0.16, width: bounds.width, height: 20)

        let pw: CGFloat = min(380, bounds.width * 0.86)
        let ph: CGFloat = 260
        menuPanel.frame = CGRect(x: (bounds.width - pw)/2, y: (bounds.height - ph)/2, width: pw, height: ph)
        menuTitle.frame = CGRect(x: 0, y: 34, width: pw, height: 44)
        finalScore.frame = CGRect(x: 0, y: 92, width: pw, height: 26)
        playButton.frame = CGRect(x: (pw - 190)/2, y: 150, width: 190, height: 56)
    }

    @objc private func playTapped() {
        onRestart?()
        menuPanel.isHidden = true
    }

    @objc private func tick() {
        let state = fly_state()
        scoreLabel.text = "\(fly_score())"
        bestLabel.text = "BEST \(fly_best())   ·   anelli \(fly_rings())"
        speedLabel.text = String(format: "%.0f km/h", fly_speed() * 3.6)
        altLabel.text = String(format: "%.0f m", fly_altitude())
        boostBar.frame.size.width = boostTrack.bounds.width * CGFloat(fly_boost())

        let heat = CGFloat(fly_laser_heat())
        heatBar.frame.size.width = heatTrack.bounds.width * heat
        heatBar.backgroundColor = heat >= 0.85
            ? UIColor(red: 0.55, green: 0.05, blue: 0.05, alpha: 1)   // surriscaldato
            : UIColor(red: 1, green: 0.3 - 0.15 * heat, blue: 0.25, alpha: 1)

        if state == 0 { // menu (dopo crash)
            menuPanel.isHidden = false
            finalScore.text = "Punteggio: \(fly_score())  ·  Anelli: \(fly_rings())"
        }
        hintLabel.isHidden = (state != 1) || (fly_time() > 6.0)
    }
}

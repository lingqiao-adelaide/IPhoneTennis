import UIKit

/// 握持说明 + 方向校准 + 自检。开始游戏前必经。
final class CalibrationViewController: UIViewController {
    var onReady: (() -> Void)?
    var onBack: (() -> Void)?

    private let arrow = PointingArrowView()
    private let liveLabel = UILabel()
    private let swingLabel = UILabel()
    private let calibrateButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let mirrorButton = UIButton(type: .system)
    private let biasLabel = UILabel()


    private var observer: UUID?
    private var lastSwingTime: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.26, alpha: 1)
        let motionOK = GameSession.shared.motion.isAvailable

        let title = UILabel()
        title.text = "How to hold & calibrate"
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .white

        let steps = UILabel()
        steps.numberOfLines = 0
        steps.font = .systemFont(ofSize: 13, weight: .regular)
        steps.textColor = UIColor(white: 0.9, alpha: 1)
        steps.text = """
        Grip: hold the lower half of the phone like a racket handle. Top of the phone = racket head. \
        The screen may face any direction.

        Tap "Start calibration". The steps appear on the TV (or here if no TV is connected): \
        pointing the phone at the TV (sets "forward"), then a few swings (straight, left, right, soft, hard, chop, lift) \
        so the app learns YOUR thresholds.

        Afterwards swing once here to check the reading. Left/right swapped? Tap Mirror. \
        Redo calibration after changing grip or hand, or if aim starts drifting.
        """

        func label(_ l: UILabel, size: CGFloat, color: UIColor) {
            l.font = .monospacedDigitSystemFont(ofSize: size, weight: .medium)
            l.textColor = color
            l.textAlignment = .center
            l.numberOfLines = 0
        }
        label(liveLabel, size: 14, color: .white)
        label(swingLabel, size: 13, color: .systemCyan)
        swingLabel.text = motionOK ? "Try one swing toward the TV" : "Simulator has no sensors; self-check unavailable"

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Start calibration"
        cfg.baseBackgroundColor = .systemOrange
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        calibrateButton.configuration = cfg
        calibrateButton.addTarget(self, action: #selector(startSession), for: .touchUpInside)

        var cfg2 = UIButton.Configuration.filled()
        cfg2.title = "Start Match"
        cfg2.baseBackgroundColor = .systemGreen
        cfg2.baseForegroundColor = .white
        cfg2.cornerStyle = .medium
        startButton.configuration = cfg2
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)

        label(biasLabel, size: 13, color: UIColor(white: 0.85, alpha: 1))
        updateBiasLabel()

        mirrorButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        mirrorButton.addTarget(self, action: #selector(mirrorTapped), for: .touchUpInside)
        updateMirrorTitle()

        let back = UIButton(type: .system)
        back.setTitle("← Back", for: .normal)
        back.setTitleColor(UIColor(white: 0.8, alpha: 1), for: .normal)
        back.addTarget(self, action: #selector(backTapped), for: .touchUpInside)

        let left = UIStackView(arrangedSubviews: [title, steps])
        left.axis = .vertical
        left.spacing = 6
        left.alignment = .leading

        let right = UIStackView(arrangedSubviews: [arrow, liveLabel, swingLabel, calibrateButton, biasLabel, mirrorButton, startButton])
        right.axis = .vertical
        right.spacing = 6
        right.alignment = .fill

        let root = UIStackView(arrangedSubviews: [left, right])
        root.axis = .horizontal
        root.spacing = 24
        root.alignment = .top
        root.distribution = .fillEqually
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(back)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 26),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            arrow.heightAnchor.constraint(equalToConstant: 84),
            calibrateButton.heightAnchor.constraint(equalToConstant: 38),
            startButton.heightAnchor.constraint(equalToConstant: 40),
            back.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        ])

        observer = GameSession.shared.addObserver { [weak self] in self?.refresh() }
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        CalibrationFlow.shared.pageVisible = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        CalibrationFlow.shared.pageVisible = false
    }

    deinit { GameSession.shared.removeObserver(observer) }

    private func refresh() {
        let m = GameSession.shared.motion
        let pose = m.live
        arrow.heading = pose.pointingDegrees
        arrow.calibrated = m.isCalibrated
        if m.isAvailable {
            liveLabel.text = String(format: "Pointing %+.0f°   Face tilt %+.0f°   %@",
                                    pose.pointingDegrees, pose.elevationDegrees,
                                    m.isCalibrated ? "Calibrated ✓" : "Not calibrated")
        } else {
            liveLabel.text = "Simulator: no sensors, you can start directly"
        }
        if biasLabel.text?.hasPrefix("Forward not") == true && m.isCalibrated { updateBiasLabel() }
        if let sw = m.lastSwing, sw.timestamp != lastSwingTime {
            lastSwingTime = sw.timestamp
            let dir = SwingProfile.shared.direction(sw.headingDegrees).uppercased()
            let height = SwingProfile.shared.face(sw.elevationDegrees).uppercased()
            let power = PowerMeterView.powerClass(sw.handSpeed).name.uppercased()
            swingLabel.text = String(format: "Swing: heading %+.0f° %@ (face %+.0f° / path %+.0f°)  tilt %+.0f° (%@; face %+.0f° / path %+.0f°)  hand %.1f m/s %@",
                                     sw.headingDegrees, dir, sw.faceHeadingDegrees, sw.pathHeadingDegrees, sw.elevationDegrees, height, sw.faceElevationDegrees, sw.pathElevationDegrees, sw.handSpeed, power)
        }
    }

    @objc private func startSession() {
        guard GameSession.shared.motion.isAvailable else {
            biasLabel.text = "Simulator has no sensors; calibration unavailable"
            return
        }
        let vc = CalibrationSessionViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.onFinished = { [weak self] in self?.updateBiasLabel(); self?.arrow.flash() }
        present(vc, animated: true)
    }

    private func updateBiasLabel() {
        let m = GameSession.shared.motion
        let cal = m.isCalibrated ? "Forward set ✓" : "Forward not set"
        if SwingProfile.shared.isCustom {
            biasLabel.text = cal + " · Your profile: " + SwingProfile.shared.summary
            biasLabel.textColor = .systemGreen
        } else {
            biasLabel.text = cal + " · Default thresholds: " + SwingProfile.shared.summary
            biasLabel.textColor = m.isCalibrated ? UIColor(white: 0.85, alpha: 1) : .systemOrange
        }
    }

    private func updateMirrorTitle() {
        let on = GameSession.shared.motion.mirrored
        mirrorButton.setTitle(on ? "Left/right swapped? Mirror: ON (tap to turn off)" : "Left/right swapped? Mirror: OFF (tap to turn on)", for: .normal)
        mirrorButton.setTitleColor(on ? .systemOrange : UIColor(white: 0.8, alpha: 1), for: .normal)
    }

    @objc private func mirrorTapped() {
        GameSession.shared.motion.mirrored.toggle()
        updateMirrorTitle()
    }

    @objc private func startTapped() {
        let m = GameSession.shared.motion
        if m.isAvailable && !m.isCalibrated {
            let alert = UIAlertController(title: "Not calibrated", message: "Without calibration, left/right aim will be random. Run calibration first?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Calibrate first", style: .cancel) { [weak self] _ in self?.startSession() })
            alert.addAction(UIAlertAction(title: "Start anyway", style: .default) { [weak self] _ in self?.onReady?() })
            present(alert, animated: true)
            return
        }
        onReady?()
    }

    @objc private func backTapped() { onBack?() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}

/// 俯视示意：上方是电视，箭头表示手机顶端当前指向。
final class PointingArrowView: UIView {
    var heading = 0.0 { didSet { setNeedsDisplay() } }
    var calibrated = false { didSet { setNeedsDisplay() } }
    private var flashUntil: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func flash() {
        flashUntil = ProcessInfo.processInfo.systemUptime + 0.6
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let c = CGPoint(x: rect.midX, y: rect.midY + 8)
        let r = min(rect.width, rect.height) / 2 - 14

        // 电视
        let tv = CGRect(x: c.x - 36, y: rect.minY, width: 72, height: 10)
        ctx.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        ctx.fill(tv)
        let tvText = NSAttributedString(string: "TV", attributes: [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor(white: 0.85, alpha: 1)])
        tvText.draw(at: CGPoint(x: c.x + 42, y: rect.minY - 2))

        let flashing = ProcessInfo.processInfo.systemUptime < flashUntil
        ctx.setStrokeColor((flashing ? UIColor.systemGreen : (calibrated ? UIColor.systemCyan : UIColor(white: 0.5, alpha: 1))).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

        // 箭头：0° 朝上（电视方向），右正
        let a = CGFloat(deg2rad(heading)) - .pi / 2
        let tip = CGPoint(x: c.x + cos(a) * r * 0.9, y: c.y + sin(a) * r * 0.9)
        ctx.setStrokeColor(UIColor.systemOrange.cgColor)
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        ctx.move(to: c)
        ctx.addLine(to: tip)
        ctx.strokePath()
        let headLen: CGFloat = 12
        for side in [-1.0, 1.0] {
            let ang = a + .pi + CGFloat(side) * 0.5
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: tip.x + cos(ang) * headLen, y: tip.y + sin(ang) * headLen))
            ctx.strokePath()
        }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8))
    }
}

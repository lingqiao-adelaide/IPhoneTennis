import UIKit

/// 电视接入后手机上显示的“球拍面板”：不渲染 3D，只给大字提示和设置。
final class ControllerViewController: UIViewController {
    var onExit: (() -> Void)?
    private let title_ = UILabel()
    private let statusLabel = UILabel()
    private let scoreLabel = UILabel()
    private let liveLabel = UILabel()
    private let feedbackLabel = UILabel()
    private let gauge = RacketGaugeView()
    private let swingPanel = SwingInfoPanel()
    private let tipLabel = UILabel()
    private let pauseButton = UIButton(type: .system)
    private let latencyStepper = UIStepper()
    private let latencyLabel = UILabel()
    private var observer: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)

        func label(_ l: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor = .white) {
            l.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.numberOfLines = 0
            l.textAlignment = .center
        }
        label(title_, size: 16, weight: .semibold, color: UIColor(white: 0.7, alpha: 1))
        title_.text = "Game is on the TV · your phone is the racket (screen = racket face)"
        label(statusLabel, size: 34, weight: .heavy)
        label(scoreLabel, size: 30, weight: .black, color: .systemYellow)
        label(liveLabel, size: 16, weight: .medium)
        label(feedbackLabel, size: 14, weight: .regular, color: UIColor(white: 0.85, alpha: 1))
        label(latencyLabel, size: 14, weight: .regular)
        label(tipLabel, size: 13, weight: .semibold, color: .systemCyan)

        latencyStepper.minimumValue = 0
        latencyStepper.maximumValue = 500
        latencyStepper.stepValue = 50
        latencyStepper.value = GameSession.shared.latencyCompensation * 1000
        latencyStepper.addTarget(self, action: #selector(latencyChanged), for: .valueChanged)

        let calibrate = UIButton(type: .system)
        calibrate.setTitle("Calibrate (point the top at the TV, then tap)", for: .normal)
        calibrate.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        calibrate.addTarget(self, action: #selector(calibrate(_:)), for: .touchUpInside)
        let restartButton = UIButton(type: .system)
        restartButton.setTitle("Restart", for: .normal)
        restartButton.addTarget(self, action: #selector(restartTapped), for: .touchUpInside)
        let exitButton = UIButton(type: .system)
        exitButton.setTitle("Quit Game", for: .normal)
        exitButton.setTitleColor(.systemRed, for: .normal)
        exitButton.addTarget(self, action: #selector(exitTapped), for: .touchUpInside)
        pauseButton.setTitle("Pause", for: .normal)
        pauseButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        let bottomRow = UIStackView(arrangedSubviews: [pauseButton, restartButton, exitButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 24

        let latencyRow = UIStackView(arrangedSubviews: [latencyLabel, latencyStepper])
        latencyRow.axis = .horizontal
        latencyRow.spacing = 12
        latencyRow.alignment = .center

        let left = UIStackView(arrangedSubviews: [title_, statusLabel, scoreLabel, swingPanel, feedbackLabel])
        left.axis = .vertical
        left.spacing = 10
        left.alignment = .center

        let right = UIStackView(arrangedSubviews: [gauge, liveLabel, tipLabel, calibrate, latencyRow, bottomRow])
        right.axis = .vertical
        right.spacing = 10
        right.alignment = .center

        let root = UIStackView(arrangedSubviews: [left, right])
        root.axis = .horizontal
        root.distribution = .fillEqually
        root.alignment = .center
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            gauge.widthAnchor.constraint(equalToConstant: 120),
            gauge.heightAnchor.constraint(equalToConstant: 120),
            swingPanel.widthAnchor.constraint(equalToConstant: 340),
        ])

        observer = GameSession.shared.addObserver { [weak self] in self?.refresh() }
        refresh()
    }

    deinit { GameSession.shared.removeObserver(observer) }

    private var tickCount = 0

    private func set(_ label: UILabel, _ text: String) {
        if label.text != text { label.text = text }
    }

    private func refresh() {
        tickCount &+= 1
        guard tickCount % 2 == 0 else { return }
        let s = GameSession.shared
        let pt = s.userPaused ? "Resume" : "Pause"
        if pauseButton.title(for: .normal) != pt { pauseButton.setTitle(pt, for: .normal) }
        if s.userPaused {
            set(statusLabel, "PAUSED")
            statusLabel.textColor = .systemYellow
            view.backgroundColor = UIColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)
        } else if s.inWindow {
            set(statusLabel, "SWING!")
            statusLabel.textColor = .yellow
            view.backgroundColor = UIColor(red: 0.25, green: 0.2, blue: 0.0, alpha: 1)
        } else {
            set(statusLabel, s.message.isEmpty ? "Waiting for the ball…" : s.message)
            statusLabel.textColor = s.messageIsGood ? .white : UIColor(red: 1, green: 0.6, blue: 0.55, alpha: 1)
            view.backgroundColor = UIColor(red: 0.05, green: 0.1, blue: 0.2, alpha: 1)
        }
        set(scoreLabel, "Games \(s.match.gamesText)   ·   \(s.match.pointsText)\nLevel \(s.level)  ·  Rally \(s.rallyHits)")
        let pose = s.motion.live
        set(liveLabel, String(format: "Face tilt %+.0f°   Heading %+.0f°", pose.elevationDegrees, pose.headingDegrees))
        gauge.elevation = pose.elevationDegrees
        gauge.heading = pose.headingDegrees
        gauge.active = s.inWindow
        set(feedbackLabel, s.lastSwingFeedback)
        swingPanel.update(swing: s.motion.lastSwing, timing: s.lastSwingTiming, resultText: s.lastSwingResult)
        set(tipLabel, s.coachTip.isEmpty ? "" : "TIP: " + s.coachTip)
        set(latencyLabel, "TV latency offset \(Int(s.latencyCompensation * 1000)) ms")
    }

    @objc private func latencyChanged() {
        GameSession.shared.latencyCompensation = latencyStepper.value / 1000
    }

    @objc private func calibrate(_ sender: UIButton) { GameSession.shared.calibrate() }
    @objc private func restartTapped() { GameSession.shared.restart() }
    @objc private func exitTapped() { onExit?() }
    @objc private func pauseTapped() { GameSession.shared.togglePause() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}

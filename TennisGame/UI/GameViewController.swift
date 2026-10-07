import UIKit
import SceneKit

/// 3D 游戏画面。`.phone` 模式带触摸调试和按钮；`.television` 模式纯显示。
final class GameViewController: UIViewController {
    enum Mode { case phone, television }

    let mode: Mode
    var onExit: (() -> Void)?
    private let scnView = SCNView()
    private let hud = HUDView()
    private let calibrationOverlay = CalibrationStepView()
    private var observer: UUID?
    private let latencyButton = UIButton(type: .system)
    private let pauseButton = UIButton(type: .system)

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let session = GameSession.shared

        scnView.scene = session.court.scene
        scnView.pointOfView = session.court.cameraNode
        scnView.antialiasingMode = .multisampling2X
        scnView.rendersContinuously = true
        scnView.preferredFramesPerSecond = 60
        scnView.isJitteringEnabled = false
        scnView.backgroundColor = .black
        scnView.frame = view.bounds
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(scnView)

        hud.frame = view.bounds
        hud.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hud)

        if mode == .phone {
            setupPhoneControls()
            hud.hint = session.motion.isAvailable
                ? ""
                : "Simulator: swipe to simulate a swing (left/right = direction, up/down = tilt, speed = power)"
        } else {
            hud.hint = ""
            hud.idleMessage = "Tap “Start Game” on your phone"
            calibrationOverlay.frame = view.bounds
            calibrationOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            calibrationOverlay.isHidden = true
            view.addSubview(calibrationOverlay)
        }

        observer = session.addObserver { [weak self] in
            guard let self else { return }
            self.hud.refresh(from: session)
            if self.mode == .television {
                let flow = CalibrationFlow.shared
                self.calibrationOverlay.isHidden = !flow.isActive
                if flow.isActive { self.calibrationOverlay.render(flow) }
                self.hud.idleMessage = flow.pageVisible
                    ? "Calibration: tap “Start calibration” on your phone and follow the steps here"
                    : "Tap “Start Game” on your phone"
            }
            if self.mode == .phone {
                self.latencyButton.setTitle("Latency \(Int(session.latencyCompensation * 1000))ms", for: .normal)
                let t = session.userPaused ? "Resume" : "Pause"
                if self.pauseButton.title(for: .normal) != t { self.pauseButton.setTitle(t, for: .normal) }
            }
        }
    }

    deinit { GameSession.shared.removeObserver(observer) }

    private func setupPhoneControls() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(pan)

        let calibrate = makeButton("Recalibrate", action: #selector(calibrate))
        let restartButton = makeButton("Restart", action: #selector(restartTapped))
        let exit = makeButton("Quit", action: #selector(exitTapped))
        pauseButton.setTitle("Pause", for: .normal)
        styleButton(pauseButton)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        latencyButton.setTitle("Latency 0ms", for: .normal)
        styleButton(latencyButton)
        latencyButton.addTarget(self, action: #selector(cycleLatency), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [pauseButton, calibrate, latencyButton, restartButton, exit])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 272),
        ])
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        styleButton(b)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func styleButton(_ b: UIButton) {
        b.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        b.setTitleColor(.white, for: .normal)
        b.backgroundColor = UIColor(white: 0, alpha: 0.5)
        b.layer.cornerRadius = 6
        b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 7, bottom: 4, right: 7)
    }

    @objc private func calibrate() { GameSession.shared.calibrate() }

    @objc private func restartTapped() { GameSession.shared.restart() }
    @objc private func pauseTapped() { GameSession.shared.togglePause() }
    @objc private func exitTapped() { onExit?() }

    @objc private func cycleLatency() {
        let steps = [0.0, 0.1, 0.2, 0.3]
        let cur = GameSession.shared.latencyCompensation
        let next = steps.first { $0 > cur + 0.001 } ?? 0
        GameSession.shared.latencyCompensation = next
    }

    /// 模拟器 / 调试：滑动一下当作一次挥拍。
    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard g.state == .ended else { return }
        let tr = g.translation(in: view)
        let v = g.velocity(in: view)
        let heading = clamp(Double(tr.x) / 4.0, -50, 50)
        let elevation = clamp(Double(-tr.y) / 4.0, -10, 60)
        let handSpeed = clamp(Double(hypot(v.x, v.y)) / 250.0, 2, 11)
        GameSession.shared.motion.injectSwing(heading: heading, elevation: elevation, handSpeed: handSpeed)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

import UIKit

/// 校准会话的状态机，和显示在哪块屏幕无关：电视和手机都从这里读状态来画。
/// 第 0 步对正方向（顶端指向电视、保持静止自动完成），之后 7 组动作采样学出个人档案。
final class CalibrationFlow {
    static let shared = CalibrationFlow()

    struct Step {
        let key: String
        let title: String
        let detail: String
        let count: Int          // 0 = 对正方向步骤
    }
    let steps: [Step] = [
        Step(key: "aim",      title: "Point the TOP of the phone at the TV",
             detail: "Hold it the way you will swing. Keep still for a moment and it sets automatically.", count: 0),
        Step(key: "straight", title: "Swing STRAIGHT at the TV", detail: "Normal power, 5 times.", count: 5),
        Step(key: "left",     title: "Swing aiming LEFT", detail: "5 times.", count: 5),
        Step(key: "right",    title: "Swing aiming RIGHT", detail: "5 times.", count: 5),
        Step(key: "soft",     title: "Swing SOFT", detail: "A gentle tap, 5 times.", count: 5),
        Step(key: "hard",     title: "Swing HARD", detail: "As fast as you comfortably can, 5 times.", count: 5),
        Step(key: "chop",     title: "CHOP DOWN", detail: "Close the face, like a smash. 5 times.", count: 5),
        Step(key: "lift",     title: "LIFT UP", detail: "Open the face, like a lob. 5 times.", count: 5),
    ]

    private(set) var isActive = false
    private(set) var finished = false
    private(set) var index = 0
    private(set) var progressText = ""
    private(set) var feedbackText = ""
    private(set) var summary = ""
    /// 手机停在校准页（还没开始会话）时为 true，电视上据此显示引导。
    var pageVisible = false

    private var samples: [String: [SwingEvent]] = [:]
    private var aimDone = false
    private var stepStartedAt: TimeInterval = 0
    /// 两步之间的准备时间：显示下一步动作，倒计时结束才开始采样，期间的挥拍不算
    static let pauseBetweenSteps = 2.5
    private(set) var readyUntil: TimeInterval = 0
    var isGettingReady: Bool { isActive && !finished && ProcessInfo.processInfo.systemUptime < readyUntil }
    private let tick = UIImpactFeedbackGenerator(style: .light)
    private let done = UINotificationFeedbackGenerator()

    var currentStep: Step { steps[min(index, steps.count - 1)] }
    var isAimStep: Bool { !finished && currentStep.count == 0 }

    func start() {
        samples.removeAll()
        index = 0
        finished = false
        aimDone = false
        isActive = true
        GameSession.shared.motion.headingBias = 0      // 采样用原始方向角
        beginStep()
    }

    func cancel() {
        guard isActive else { return }
        isActive = false
        finished = true
        GameSession.shared.motion.cancelCapture()
        GameSession.shared.motion.headingBias = SwingProfile.shared.headingBias
    }

    func close() {
        isActive = false
    }

    /// 每帧调用：自动对正、刷新进度文字。
    func update() {
        guard isActive, !finished else { return }
        let m = GameSession.shared.motion
        let step = currentStep
        let now = ProcessInfo.processInfo.systemUptime
        if now < readyUntil {
            progressText = String(format: "Get ready… %.0f", ceil(readyUntil - now))
            return
        }
        if step.count > 0 && !captureStarted {
            captureStarted = true
            stepStartedAt = now
            feedbackText = ""
            progressText = "\(step.count) more"
            m.captureSwings(count: step.count) { [weak self] events in
                guard let self, self.isActive, !self.finished else { return }
                self.samples[step.key] = events
                self.done.notificationOccurred(.success)
                self.advance()
            }
        }
        if step.count == 0 {
            let now = ProcessInfo.processInfo.systemUptime
            if !m.isAvailable {
                progressText = "No sensors (simulator)"
            } else if now - stepStartedAt > 1.0 && m.live.stillSeconds >= 1.5 {
                setForwardNow()
            } else {
                progressText = "Hold still…"
            }
        } else {
            let remaining = m.captureRemaining
            progressText = remaining > 0 ? "\(remaining) more" : "…"
            if let sw = m.lastSwing, sw.timestamp > stepStartedAt {
                feedbackText = String(format: "Last: heading %+.0f°  tilt %+.0f°  hand %.1f m/s", sw.headingDegrees, sw.elevationDegrees, sw.handSpeed)
            }
        }
    }

    func setForwardNow() {
        guard isActive, !finished, isAimStep, !aimDone else { return }
        aimDone = true
        GameSession.shared.motion.calibrateForward()
        tick.impactOccurred()
        progressText = "Forward set ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.advance() }
    }

    private var captureStarted = false

    private func beginStep() {
        let step = currentStep
        let now = ProcessInfo.processInfo.systemUptime
        stepStartedAt = now
        feedbackText = ""
        captureStarted = false
        if step.count == 0 {
            progressText = "Hold still…"
            readyUntil = 0
        } else {
            // 先给一段准备时间，采样在 update() 里倒计时结束后才开始
            readyUntil = now + CalibrationFlow.pauseBetweenSteps
            progressText = "Get ready…"
        }
    }

    private func advance() {
        guard isActive, !finished else { return }
        index += 1
        if index >= steps.count { finish() } else { beginStep() }
    }

    private func finish() {
        finished = true
        let p = SwingProfile.build(straight: samples["straight"] ?? [], left: samples["left"] ?? [],
                                   right: samples["right"] ?? [], soft: samples["soft"] ?? [],
                                   hard: samples["hard"] ?? [], chop: samples["chop"] ?? [], lift: samples["lift"] ?? [])
        SwingProfile.shared = p
        GameSession.shared.motion.headingBias = p.headingBias
        summary = p.summary
        progressText = "✓"
        feedbackText = ""
    }
}

/// 校准会话的大字引导画面，电视和手机共用。
final class CalibrationStepView: UIView {
    private let stepLabel = UILabel()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressLabel = UILabel()
    private let feedbackLabel = UILabel()
    private let arrow = PointingArrowView()
    private var lastIndex = -1
    private var lastFinished = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.04, green: 0.10, blue: 0.22, alpha: 1)
        func label(_ l: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
            l.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.textAlignment = .center
            l.numberOfLines = 0
        }
        label(stepLabel, size: 16, weight: .semibold, color: UIColor(white: 0.7, alpha: 1))
        label(titleLabel, size: 36, weight: .black, color: .white)
        label(detailLabel, size: 18, weight: .medium, color: UIColor(white: 0.85, alpha: 1))
        label(progressLabel, size: 52, weight: .black, color: .systemYellow)
        label(feedbackLabel, size: 14, weight: .regular, color: .systemCyan)

        let stack = UIStackView(arrangedSubviews: [stepLabel, titleLabel, detailLabel, progressLabel, feedbackLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(arrow)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 60),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -22),
            stack.widthAnchor.constraint(equalTo: safeAreaLayoutGuide.widthAnchor, multiplier: 0.62),
            arrow.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 30),
            arrow.centerYAnchor.constraint(equalTo: centerYAnchor),
            arrow.widthAnchor.constraint(equalToConstant: 160),
            arrow.heightAnchor.constraint(equalToConstant: 160),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func render(_ flow: CalibrationFlow) {
        let m = GameSession.shared.motion
        if flow.finished && flow.isActive {
            if !lastFinished {
                lastFinished = true
                stepLabel.text = "Calibration complete"
                titleLabel.text = "You're set!"
                detailLabel.text = "Your thresholds:\n" + flow.summary
                progressLabel.textColor = .systemGreen
                arrow.isHidden = true
            }
            progressLabel.text = "✓"
            feedbackLabel.text = "Tap Done on your phone"
            return
        }
        lastFinished = false
        if flow.index != lastIndex {
            lastIndex = flow.index
            let step = flow.currentStep
            stepLabel.text = "Step \(flow.index + 1) of \(flow.steps.count)"
            titleLabel.text = step.title
            detailLabel.text = step.detail
            progressLabel.textColor = .systemYellow
            arrow.isHidden = step.count != 0
        }
        if progressLabel.text != flow.progressText { progressLabel.text = flow.progressText }
        if feedbackLabel.text != flow.feedbackText { feedbackLabel.text = flow.feedbackText }
        if flow.isAimStep {
            arrow.heading = m.live.pointingDegrees
            arrow.calibrated = m.isCalibrated
        }
    }
}

/// 手机上的会话页。连着电视时只放 Cancel / Set forward / Done，引导看电视；没电视时显示完整引导。
final class CalibrationSessionViewController: UIViewController {
    var onFinished: (() -> Void)?

    private let flow = CalibrationFlow.shared
    private let stepView = CalibrationStepView()
    private let remoteLabel = UILabel()
    private let remoteProgress = UILabel()
    private let actionButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var observer: UUID?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.10, blue: 0.22, alpha: 1)

        stepView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stepView)

        remoteLabel.text = "Follow the instructions on the TV"
        remoteLabel.font = .systemFont(ofSize: 26, weight: .bold)
        remoteLabel.textColor = .white
        remoteLabel.textAlignment = .center
        remoteLabel.numberOfLines = 0
        remoteProgress.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        remoteProgress.textColor = .systemYellow
        remoteProgress.textAlignment = .center
        remoteProgress.numberOfLines = 0

        var cfg = UIButton.Configuration.filled()
        cfg.title = "Set forward now"
        cfg.baseBackgroundColor = .systemOrange
        cfg.baseForegroundColor = .white
        cfg.cornerStyle = .medium
        actionButton.configuration = cfg
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)

        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.setTitleColor(UIColor(white: 0.8, alpha: 1), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let remote = UIStackView(arrangedSubviews: [remoteLabel, remoteProgress])
        remote.axis = .vertical
        remote.spacing = 16
        remote.alignment = .center
        remote.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(remote)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            stepView.topAnchor.constraint(equalTo: view.topAnchor),
            stepView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stepView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stepView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            remote.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            remote.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
            remote.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.7),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
            actionButton.widthAnchor.constraint(equalToConstant: 220),
            actionButton.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: 60),
            actionButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        ])
        view.bringSubviewToFront(actionButton)
        view.bringSubviewToFront(cancelButton)

        flow.start()
        observer = GameSession.shared.addObserver { [weak self] in self?.refresh() }
        refresh()
    }

    deinit { GameSession.shared.removeObserver(observer) }

    private func refresh() {
        flow.update()
        let tv = DisplayRouter.shared.externalConnected
        stepView.isHidden = tv
        remoteLabel.isHidden = !tv
        remoteProgress.isHidden = !tv
        if tv {
            if flow.finished {
                remoteLabel.text = "Calibration complete"
                remoteProgress.text = "✓"
            } else {
                remoteLabel.text = "Follow the instructions on the TV"
                remoteProgress.text = "Step \(flow.index + 1)/\(flow.steps.count): \(flow.currentStep.title)\n\(flow.progressText)"
            }
        } else {
            stepView.render(flow)
        }
        if flow.finished {
            actionButton.isHidden = false
            actionButton.configuration?.title = "Done"
            actionButton.configuration?.baseBackgroundColor = .systemGreen
            cancelButton.isHidden = true
        } else {
            actionButton.isHidden = !flow.isAimStep
            actionButton.configuration?.title = "Set forward now"
            actionButton.configuration?.baseBackgroundColor = .systemOrange
        }
    }

    @objc private func actionTapped() {
        if flow.finished {
            flow.close()
            dismiss(animated: true) { [weak self] in self?.onFinished?() }
        } else {
            flow.setForwardNow()
        }
    }

    @objc private func cancelTapped() {
        flow.cancel()
        flow.close()
        dismiss(animated: true) { [weak self] in self?.onFinished?() }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}

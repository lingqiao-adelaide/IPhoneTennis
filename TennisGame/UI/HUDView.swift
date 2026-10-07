import UIKit

/// 叠在 3D 画面上的信息层：比分、提示、实时拍面角度、来球/回球数据、小地图。
final class HUDView: UIView {
    private let scoreboard = ScoreboardView()
    private let messageLabel = UILabel()
    private let liveLabel = UILabel()
    private let gauge = RacketGaugeView()
    private let incomingLabel = UILabel()
    private let shotLabel = UILabel()
    private let swingNowLabel = UILabel()
    private let hintLabel = UILabel()
    private let miniCourt = MiniCourtView()
    private let swingPanel = SwingInfoPanel()
    private let tipLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        func style(_ l: UILabel, size: CGFloat, weight: UIFont.Weight = .semibold, color: UIColor = .white) {
            l.font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.layer.shadowColor = UIColor.black.cgColor
            l.layer.shadowOpacity = 0.9
            l.layer.shadowRadius = 2
            l.layer.shadowOffset = CGSize(width: 0, height: 1)
            l.numberOfLines = 0
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
        }
        scoreboard.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scoreboard)
        style(messageLabel, size: 30, weight: .heavy)
        messageLabel.textAlignment = .center
        style(liveLabel, size: 12)
        liveLabel.textAlignment = .right
        style(incomingLabel, size: 14, weight: .medium, color: UIColor(white: 0.95, alpha: 1))
        style(shotLabel, size: 14, weight: .medium, color: .systemCyan)
        style(swingNowLabel, size: 44, weight: .black, color: .yellow)
        swingNowLabel.text = "SWING!"
        swingNowLabel.isHidden = true
        style(hintLabel, size: 12, weight: .regular, color: UIColor(white: 0.85, alpha: 1))

        gauge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gauge)
        miniCourt.translatesAutoresizingMaskIntoConstraints = false
        addSubview(miniCourt)
        swingPanel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(swingPanel)
        style(tipLabel, size: 13, weight: .semibold, color: .white)
        tipLabel.backgroundColor = UIColor(red: 0.0, green: 0.35, blue: 0.45, alpha: 0.75)
        tipLabel.layer.cornerRadius = 8
        tipLabel.layer.masksToBounds = true
        tipLabel.textAlignment = .left
        tipLabel.isHidden = true

        let g = safeAreaLayoutGuide
        let messageCenter = messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor, constant: 90)
        messageCenter.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scoreboard.leadingAnchor.constraint(equalTo: swingPanel.trailingAnchor, constant: 16),
            scoreboard.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),

            swingPanel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            swingPanel.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            swingPanel.widthAnchor.constraint(equalToConstant: 340),

            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: swingPanel.trailingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: gauge.leadingAnchor, constant: -8),
            messageLabel.topAnchor.constraint(equalTo: scoreboard.bottomAnchor, constant: 6),
            messageCenter,

            gauge.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14),
            gauge.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            gauge.widthAnchor.constraint(equalToConstant: 96),
            gauge.heightAnchor.constraint(equalToConstant: 96),

            liveLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14),
            liveLabel.topAnchor.constraint(equalTo: gauge.bottomAnchor, constant: 2),

            tipLabel.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14),
            tipLabel.topAnchor.constraint(equalTo: liveLabel.bottomAnchor, constant: 6),
            tipLabel.widthAnchor.constraint(equalToConstant: 250),

            miniCourt.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -14),
            miniCourt.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
            miniCourt.widthAnchor.constraint(equalToConstant: 110),
            miniCourt.heightAnchor.constraint(equalToConstant: 170),

            shotLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            shotLabel.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -10),
            shotLabel.trailingAnchor.constraint(lessThanOrEqualTo: miniCourt.leadingAnchor, constant: -12),

            incomingLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            incomingLabel.bottomAnchor.constraint(equalTo: shotLabel.topAnchor, constant: -4),
            incomingLabel.trailingAnchor.constraint(lessThanOrEqualTo: miniCourt.leadingAnchor, constant: -12),

            hintLabel.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            hintLabel.bottomAnchor.constraint(equalTo: incomingLabel.topAnchor, constant: -6),

            swingNowLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            swingNowLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 40),

        ])
    }

    var hint: String? {
        get { hintLabel.text }
        set { hintLabel.text = newValue; hintLabel.isHidden = (newValue ?? "").isEmpty }
    }

    var idleMessage = ""
    private var tickCount = 0

    /// 文字只在变化时写入：每帧重设 Label 文字会触发排版，是主线程最大的常态开销。
    private func set(_ label: UILabel, _ text: String) {
        if label.text != text { label.text = text }
    }

    func refresh(from s: GameSession) {
        tickCount &+= 1
        scoreboard.refresh(from: s)
        set(messageLabel, s.userPaused ? "PAUSED" : (s.isPlaying ? s.message : idleMessage))
        let color: UIColor = s.messageIsGood ? .white : UIColor(red: 1, green: 0.55, blue: 0.5, alpha: 1)
        if messageLabel.textColor != color { messageLabel.textColor = color }
        set(incomingLabel, s.incomingSummary)
        set(shotLabel, s.lastSwingFeedback)
        if swingNowLabel.isHidden == s.inWindow { swingNowLabel.isHidden = !s.inWindow }
        swingPanel.update(swing: s.motion.lastSwing, timing: s.lastSwingTiming, resultText: s.lastSwingResult)
        let tip = s.coachTip
        if tipLabel.text != (tip.isEmpty ? nil : "  TIP: " + tip + "  ") {
            tipLabel.text = tip.isEmpty ? nil : "  TIP: " + tip + "  "
            tipLabel.isHidden = tip.isEmpty
        }

        // 角度文字、表盘、小地图 30 Hz 够用
        guard tickCount % 2 == 0 else { return }
        let pose = s.motion.live
        if s.motion.isAvailable {
            set(liveLabel, String(format: "Face tilt %+.0f°  heading %+.0f°", pose.elevationDegrees, pose.headingDegrees))
        } else {
            set(liveLabel, "No motion sensors (simulator: swipe = swing)")
        }
        gauge.elevation = pose.elevationDegrees
        gauge.heading = pose.headingDegrees
        gauge.active = s.inWindow
        miniCourt.refresh(from: s)
    }
}

/// 右上角的角度表盘：外圈指针 = 拍面水平方向，右侧竖条 = 拍面仰角。
final class RacketGaugeView: UIView {
    var elevation = 0.0 { didSet { if abs(elevation - oldValue) > 0.5 { setNeedsDisplay() } } }
    var heading = 0.0 { didSet { if abs(heading - oldValue) > 0.5 { setNeedsDisplay() } } }
    var active = false { didSet { if active != oldValue { setNeedsDisplay() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let r = rect.insetBy(dx: 4, dy: 4)
        let c = CGPoint(x: r.midX - 8, y: r.midY)
        let radius = min(r.width, r.height) / 2 - 10

        ctx.setFillColor(UIColor(white: 0, alpha: 0.45).cgColor)
        ctx.fillEllipse(in: CGRect(x: c.x - radius - 4, y: c.y - radius - 4, width: 2 * radius + 8, height: 2 * radius + 8))
        ctx.setStrokeColor((active ? UIColor.yellow : UIColor.white).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: c.x - radius, y: c.y - radius, width: 2 * radius, height: 2 * radius))

        // 正前方刻度
        ctx.move(to: CGPoint(x: c.x, y: c.y - radius))
        ctx.addLine(to: CGPoint(x: c.x, y: c.y - radius + 6))
        ctx.strokePath()

        // 方向指针（0° 指向上方 = 电视方向）
        let a = CGFloat(deg2rad(heading)) - .pi / 2
        ctx.setStrokeColor(UIColor.systemCyan.cgColor)
        ctx.setLineWidth(3)
        ctx.move(to: c)
        ctx.addLine(to: CGPoint(x: c.x + cos(a) * radius * 0.85, y: c.y + sin(a) * radius * 0.85))
        ctx.strokePath()

        // 仰角竖条：-30° 在底，+60° 在顶
        let barX = r.maxX - 8
        let top = r.minY + 4, bottom = r.maxY - 4
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.5).cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: barX, y: top))
        ctx.addLine(to: CGPoint(x: barX, y: bottom))
        ctx.strokePath()
        let t = CGFloat(clamp((elevation + 30) / 90, 0, 1))
        let y = bottom - (bottom - top) * t
        let zeroY = bottom - (bottom - top) * CGFloat(30.0 / 90.0)
        ctx.setFillColor(UIColor(white: 1, alpha: 0.6).cgColor)
        ctx.fill(CGRect(x: barX - 5, y: zeroY - 1, width: 10, height: 2))
        ctx.setFillColor(UIColor.systemOrange.cgColor)
        ctx.fillEllipse(in: CGRect(x: barX - 5, y: y - 5, width: 10, height: 10))
    }
}

/// 俯视小地图：球场、球、预测轨迹、落点、双方位置、球的飞行方向箭头。
final class MiniCourtView: UIView {
    private var ball = SIMD3<Double>(0, 0, 0)
    private var velocity = SIMD3<Double>(0, 0, 0)
    private var path: [SIMD3<Double>] = []
    private var landing: SIMD3<Double>?
    private var inBounds = true
    private var playerX = 0.0, playerZ = GameSession.playerBaseZ, opponentX = 0.0, opponentZ = GameSession.opponentBaseZ
    private var pathIsPlayers = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.45)
        layer.cornerRadius = 8
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh(from s: GameSession) {
        ball = s.ball.position
        velocity = s.ball.velocity
        path = s.currentPath?.points ?? []
        landing = s.currentPath?.firstBounce
        inBounds = s.currentPath?.inBounds ?? true
        playerX = s.playerX
        playerZ = s.playerZ
        opponentX = s.opponentX
        opponentZ = s.opponentZ
        pathIsPlayers = s.currentPathOwner == .player
        setNeedsDisplay()
    }

    private func map(_ x: Double, _ z: Double) -> CGPoint {
        // z 负方向（对手）在上
        let w = bounds.width, h = bounds.height
        let sx = w / 14.0, sz = h / 30.0
        return CGPoint(x: w / 2 + CGFloat(x) * sx, y: h / 2 + CGFloat(z) * sz)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let L = Court.halfLength, Ws = Court.halfWidthSingles
        let a = map(-Ws, -L), b = map(Ws, L)
        ctx.setFillColor(UIColor(red: 0.24, green: 0.46, blue: 0.78, alpha: 0.9).cgColor)
        ctx.fill(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        let n1 = map(-Ws - 0.6, 0), n2 = map(Ws + 0.6, 0)
        ctx.setLineWidth(2)
        ctx.move(to: n1); ctx.addLine(to: n2); ctx.strokePath()
        ctx.setLineWidth(0.5)
        let s1 = map(-Ws, Court.serviceLineZ), s2 = map(Ws, Court.serviceLineZ)
        ctx.move(to: s1); ctx.addLine(to: s2); ctx.strokePath()
        let s3 = map(-Ws, -Court.serviceLineZ), s4 = map(Ws, -Court.serviceLineZ)
        ctx.move(to: s3); ctx.addLine(to: s4); ctx.strokePath()

        if path.count > 1 {
            ctx.setStrokeColor((pathIsPlayers ? UIColor.systemCyan : UIColor.white).withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: map(path[0].x, path[0].z))
            for p in path.dropFirst() { ctx.addLine(to: map(p.x, p.z)) }
            ctx.strokePath()
        }
        if let l = landing {
            let p = map(l.x, l.z)
            ctx.setStrokeColor((inBounds ? UIColor.systemGreen : UIColor.systemRed).cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
        }

        // 玩家与对手
        let pp = map(playerX, playerZ), op = map(opponentX, opponentZ)
        ctx.setFillColor(UIColor.systemCyan.cgColor)
        ctx.fill(CGRect(x: pp.x - 5, y: pp.y - 2, width: 10, height: 4))
        ctx.setFillColor(UIColor.systemRed.cgColor)
        ctx.fill(CGRect(x: op.x - 5, y: op.y - 2, width: 10, height: 4))

        // 球 + 方向箭头
        let bp = map(ball.x, ball.z)
        let h = hypot(velocity.x, velocity.z)
        if h > 1 {
            let dx = CGFloat(velocity.x / h), dz = CGFloat(velocity.z / h)
            ctx.setStrokeColor(UIColor.yellow.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: bp)
            ctx.addLine(to: CGPoint(x: bp.x + dx * 14, y: bp.y + dz * 14))
            ctx.strokePath()
        }
        ctx.setFillColor(UIColor.yellow.cgColor)
        ctx.fillEllipse(in: CGRect(x: bp.x - 3, y: bp.y - 3, width: 6, height: 6))
    }
}

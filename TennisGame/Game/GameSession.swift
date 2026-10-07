import Foundation
import QuartzCore
import UIKit
import simd

/// 玩家最近一次回球的详细数据，供 HUD 展示。
struct ShotInfo {
    var direction: String            // 左 / 中 / 右
    var power: String                // 轻 / 中 / 重
    var handSpeed: Double
    var faceHeading: Double
    var pathHeading: Double
    var faceElevation: Double
    var pathElevation: Double
    var face: String                 // 正常 / 高吊 / 盖拍
    var headingDegrees: Double
    var elevationDegrees: Double
    var speed: Double
    var timingError: Double          // 正数 = 提前，负数 = 晚了
    var netClearance: Double?
    var landing: SIMD3<Double>?
    var inBounds: Bool
    var hitNet: Bool

    var summary: String {
        let timing = timingError >= 0 ? String(format: "%.2fs early", timingError) : String(format: "%.2fs late", -timingError)
        var s = String(format: "Shot  dir %@(%+.0f° = face %+.0f° / path %+.0f°)  power %@ (hand %.1f m/s)  tilt %@(%+.0f° = face %+.0f° / path %+.0f°)  ball %.0f m/s  timing %@",
                       direction, headingDegrees, faceHeading, pathHeading, power, handSpeed, face, elevationDegrees, faceElevation, pathElevation, speed, timing)
        if hitNet {
            s += "  →  into the net"
        } else if netClearance == nil {
            s += "  →  did not clear the net"
        } else if let c = netClearance {
            s += String(format: "  →  net clearance %+.2fm", c)
            if let l = landing {
                s += inBounds ? String(format: ", lands IN (x %+.1f, %.1fm past net)", l.x, abs(l.z))
                              : String(format: ", lands OUT (x %+.1f, %.1fm past net)", l.x, abs(l.z))
            }
        }
        return s
    }
}

/// 整个游戏的大脑：球的物理、回合状态机、击球判定、对手 AI、计分。
/// 用 CADisplayLink 驱动，与显示在哪块屏幕无关。
final class GameSession: NSObject {
    static let shared = GameSession()

    let court = CourtScene()
    let motion = SwingDetector()
    let match = MatchState()

    // 位置常量
    static let playerBaseZ = Court.halfLength + 0.9       // 玩家底线站位
    static let hitOffset = 0.6                             // 击球点在玩家身前多远
    static let racketX = 0.42                              // 球拍在身体右侧的横向偏移
    static let opponentBaseZ = -Court.halfLength - 0.6
    static let opponentReactionTime = 0.4
    static let timingWindow = 0.45                         // 可击球的时间窗口 ±秒

    // MARK: 难度等级（赢一局升一级）
    struct LevelParams {
        let errorBase: Double      // 对手每次回球的基础失误率
        let errorPerHit: Double    // 玩家每多回一拍，失误率增加
        let reaction: Double       // 对手反应时间（秒）
        let speed: Double          // 对手跑动速度（m/s）
        let maxDifficulty: Int     // 对手回球刁钻程度上限（传给 OpponentAI）
    }
    static let maxLevel = 6
    static func params(for level: Int) -> LevelParams {
        switch level {
        case 1:  return LevelParams(errorBase: 0.25, errorPerHit: 0.25, reaction: 0.7,  speed: 2.6, maxDifficulty: 1)
        case 2:  return LevelParams(errorBase: 0.15, errorPerHit: 0.18, reaction: 0.6,  speed: 3.0, maxDifficulty: 3)
        case 3:  return LevelParams(errorBase: 0.10, errorPerHit: 0.12, reaction: 0.5,  speed: 3.3, maxDifficulty: 5)
        case 4:  return LevelParams(errorBase: 0.06, errorPerHit: 0.08, reaction: 0.45, speed: 3.6, maxDifficulty: 8)
        case 5:  return LevelParams(errorBase: 0.04, errorPerHit: 0.05, reaction: 0.4,  speed: 3.9, maxDifficulty: 10)
        default: return LevelParams(errorBase: 0.02, errorPerHit: 0.03, reaction: 0.35, speed: 4.2, maxDifficulty: 12)
        }
    }
    private(set) var level = 1
    var levelParams: LevelParams { GameSession.params(for: level) }
    static let earlyBuffer = 1.0                           // 比窗口更早的挥拍会先记住，等球到了再打
    static let playerReach = 1.7
    /// 手速分界（m/s）：Light / Heavy 两档，来自个人档案
    static var lightSpeed: Double { SwingProfile.shared.heavySpeed }
    static let opponentReach = 1.6

    enum Phase {
        case waiting
        case countdown(until: Double)
        case rally
        case pointOver(until: Double)
    }

    private(set) var phase: Phase = .waiting
    private(set) var ball = BallState(position: SIMD3(0, 1.0, GameSession.opponentBaseZ + 0.4), velocity: .zero)
    private(set) var ballVisible = true
    private(set) var lastHitBy: Side = .opponent
    private(set) var playerX = 0.0
    private(set) var playerZ = GameSession.playerBaseZ
    private var playerTargetZ = GameSession.playerBaseZ
    var hitPlaneZ: Double { playerZ - GameSession.hitOffset }
    private(set) var opponentX = 0.0
    private(set) var opponentZ = GameSession.opponentBaseZ
    private var playerTargetX = 0.0
    private var opponentTargetX = 0.0
    private var opponentTargetZ = GameSession.opponentBaseZ
    private var opponentReactAt = 0.0

    /// 当前这一球的预测轨迹（谁打的都有）
    private(set) var currentPath: BallPhysics.Prediction?
    private(set) var currentPathOwner: Side = .opponent
    private(set) var pathVersion = 0
    /// 来球到达击球平面的绝对时间和状态
    private var contact: (time: Double, state: BallState)?
    private var pendingSwing: SwingEvent?
    private(set) var inWindow = false
    private var windowHapticDone = false

    private(set) var message = ""
    private(set) var messageIsGood = true
    private var messageUntil = 0.0
    private(set) var lastShot: ShotInfo?
    private(set) var lastSwingFeedback = ""
    /// 左上角面板用：上一次挥拍的时机文字和一句话结果
    private(set) var lastSwingTiming = "—"
    private(set) var lastSwingResult = ""
    /// 前几分的打法提示（右上角）。lesson 来自上一拍的结果，situational 看当前局面。
    static let tipsUntilPoints = 12
    private var coachLesson = ""
    var coachTip: String {
        guard isPlaying, match.pointsPlayed < GameSession.tipsUntilPoints else { return "" }
        switch phase {
        case .waiting:
            return ""
        case .countdown:
            if match.pointsPlayed == 0 { return "Swing when the ball reaches the yellow ring and SWING! appears." }
            return coachLesson.isEmpty ? "Topspin face + heavy swing = safe rally ball." : coachLesson
        case .pointOver:
            return coachLesson
        case .rally:
            if lastHitBy == .player { return coachLesson }
            if opponentZ > -6 { return "Opponent is at the net: open face + light swing = lob over them." }
            if opponentX < -1.5 { return "Opponent is on the LEFT: aim RIGHT (face and swing to the right)." }
            if opponentX > 1.5 { return "Opponent is on the RIGHT: aim LEFT." }
            if rallyHits >= 1 { return "Opponent on the baseline: light topspin swing = drop shot." }
            return "Topspin face + heavy swing = safe rally ball. Watch the timing."
        }
    }
    private(set) var rallyHits = 0
    private(set) var incomingSummary = ""

    /// 电视/AirPlay 画面延迟补偿（秒）：挥拍时刻按这个值往前推。
    var latencyCompensation = 0.0

    private var history: [(t: Double, s: BallState)] = []
    private var landingChecked = false
    private var opponentAttempted = false
    private var displayLink: CADisplayLink?
    private var lastTick: Double?
    private var paused = false
    private var observers: [UUID: () -> Void] = [:]

    #if DEBUG
    private var autoSwingDone = false
    private static let autoSwing: (heading: Double, elevation: Double, speed: Double, lead: Double)? = {
        guard let raw = ProcessInfo.processInfo.environment["AUTOSWING"] else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2], parts.count > 3 ? parts[3] : 0)
    }()
    #endif

    private let hitHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let windowHaptic = UIImpactFeedbackGenerator(style: .light)
    private let resultHaptic = UINotificationFeedbackGenerator()

    var now: Double { ProcessInfo.processInfo.systemUptime }

    // MARK: - 生命周期

    func start() {
        guard displayLink == nil else { return }
        motion.onSwing = { [weak self] in self?.handleSwing($0) }
        motion.start()
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        endMatch()
    }

    var isPlaying: Bool {
        if case .waiting = phase { return false }
        return true
    }

    /// 从主菜单点“开始游戏”。
    func beginMatch() {
        match.reset()
        level = 1
        userPaused = false
        lastShot = nil
        lastSwingFeedback = ""
        lastSwingTiming = "—"
        lastSwingResult = ""
        coachLesson = ""
        rallyHits = 0
        scheduleNextPoint(delay: 1.5)
        setMessage("Get ready! Opponent is about to serve", good: true, duration: 2.5)
    }

    func restart() { beginMatch() }

    /// 退出到主菜单：球场保持空闲状态。
    func endMatch() {
        phase = .waiting
        userPaused = false
        contact = nil
        pendingSwing = nil
        inWindow = false
        currentPath = nil
        pathVersion += 1
        incomingSummary = ""
        lastSwingFeedback = ""
        playerTargetX = 0
        playerTargetZ = GameSession.playerBaseZ
        playerZ = GameSession.playerBaseZ
        opponentTargetX = 0
        opponentTargetZ = GameSession.opponentBaseZ
        opponentZ = GameSession.opponentBaseZ
        ballVisible = true
        ball = BallState(position: SIMD3(opponentX, 1.2, GameSession.opponentBaseZ + 0.4), velocity: .zero)
        court.hidePath()
        message = ""
    }

    func setPaused(_ p: Bool) {
        paused = p
        lastTick = nil
    }

    /// 玩家主动暂停（和系统后台暂停分开）
    private(set) var userPaused = false
    func togglePause() {
        guard isPlaying else { return }
        userPaused.toggle()
        lastTick = nil
    }

    func calibrate() {
        motion.calibrateForward()
        setMessage("Calibrated: this direction is now forward", good: true, duration: 1.5)
    }

    func addObserver(_ block: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = block
        return id
    }

    func removeObserver(_ id: UUID?) {
        if let id { observers[id] = nil }
    }

    // MARK: - 每帧

    @objc private func tick(_ link: CADisplayLink) {
        let t = now
        let dt = min(lastTick.map { t - $0 } ?? (1.0 / 60), 0.05)
        lastTick = t
        if paused { return }
        if userPaused {
            court.update(session: self, time: t)
            for o in observers.values { o() }
            return
        }

        switch phase {
        case .waiting:
            break
        case .countdown(let until):
            if t >= until { opponentServes() }
        case .rally:
            stepRally(dt: dt, t: t)
        case .pointOver(let until):
            stepBall(dt: dt)
            if t >= until { scheduleNextPoint(delay: 0.8) }
        }
        movePlayers(dt: dt)
        if t > messageUntil { message = "" }
        court.update(session: self, time: t)
        for o in observers.values { o() }
    }

    private func stepBall(dt: Double) {
        let sub = 4
        for _ in 0..<sub { BallPhysics.step(&ball, dt: dt / Double(sub)) }
    }

    private func stepRally(dt: Double, t: Double) {
        stepBall(dt: dt)
        history.append((t, ball))
        if history.count > 90 { history.removeFirst(history.count - 90) }

        if ball.hitNet {
            if lastHitBy == .player {
                endPoint(winner: .opponent, text: "Into the net!")
            } else {
                endPoint(winner: .player, text: "Opponent hit the net, your point")
            }
            return
        }
        if ball.bounces >= 1 && !landingChecked {
            landingChecked = true
            let ownSide = lastHitBy == .player ? (ball.lastBounce?.z ?? 0) > 0 : (ball.lastBounce?.z ?? 0) < 0
            if ownSide {
                if lastHitBy == .player {
                    endPoint(winner: .opponent, text: "Did not clear the net")
                } else {
                    endPoint(winner: .player, text: "Opponent did not clear the net, your point")
                }
                return
            }
            if let b = ball.lastBounce, !Court.isInside(x: b.x, z: b.z) {
                if lastHitBy == .player {
                    let long = abs(b.z) - Court.halfLength
                    let wide = abs(b.x) - Court.halfWidthSingles
                    let why = long > wide ? String(format: "%.1fm long", long) : String(format: "%.1fm wide", wide)
                    endPoint(winner: .opponent, text: "Out! \(why)")
                } else {
                    endPoint(winner: .player, text: "Opponent hit out, your point")
                }
                return
            }
        }
        if ball.bounces >= 2 {
            if lastHitBy == .player {
                endPoint(winner: .player, text: "Winner! Opponent could not reach it")
            } else {
                endPoint(winner: .opponent, text: "Double bounce, missed")
            }
            return
        }

        switch lastHitBy {
        case .opponent:
            if let c = contact {
                let wasIn = inWindow
                inWindow = abs(c.time - t) <= GameSession.timingWindow
                if let p = pendingSwing, t >= c.time - 0.03 {
                    pendingSwing = nil
                    resolveSwing(p, timingError: GameSession.timingWindow * 0.35)
                }
                #if DEBUG
                // 调试：环境变量 AUTOSWING="方向,仰角,手速[,提前秒数]" 让玩家自动挥拍（模拟器没有传感器）
                if let auto = GameSession.autoSwing, !autoSwingDone, t >= c.time - auto.lead {
                    autoSwingDone = true
                    motion.injectSwing(heading: auto.heading, elevation: auto.elevation, handSpeed: auto.speed)
                }
                #endif
                if inWindow && !wasIn && !windowHapticDone {
                    windowHapticDone = true
                    windowHaptic.impactOccurred()
                }
            } else {
                inWindow = false
            }
            if ball.position.z > playerZ + 0.8 {
                // 球没落地就飞过了玩家：预测会出界的球放过去算你得分，否则是没接到
                if ball.bounces == 0, let path = currentPath, !path.inBounds {
                    endPoint(winner: .player, text: "Opponent hit long, your point")
                } else {
                    endPoint(winner: .opponent, text: "Missed the ball")
                }
            }
        case .player:
            inWindow = false
            if !opponentAttempted && ball.velocity.z < 0 && ball.position.z <= opponentZ + 1.0 {
                opponentAttempted = true
                let reachable = abs(ball.position.x - opponentX) <= GameSession.opponentReach
                    && ball.position.z > opponentZ - 0.8 && ball.position.y < 2.6
                let willBeIn = currentPath?.inBounds ?? true
                if reachable && willBeIn && ball.bounces <= 1 {
                    opponentReturns()
                } else if !willBeIn {
                    setMessage("Opponent let it go…", good: false, duration: 1.2)
                }
            }
            if ball.position.z < GameSession.opponentBaseZ - 6 {
                endPoint(winner: .opponent, text: "Out!")
            }
        }
    }

    private func movePlayers(dt: Double) {
        let pSpeed = 5.5
        playerX += clamp(playerTargetX - playerX, -pSpeed * dt, pSpeed * dt)
        playerZ += clamp(playerTargetZ - playerZ, -pSpeed * dt, pSpeed * dt)
        playerX = clamp(playerX, -5.5, 5.5)
        playerZ = clamp(playerZ, 1.5, GameSession.playerBaseZ + 1.0)
        // 对手有反应时间，跑动速度有限，击球后不回中：往它跑不到的地方打才能赢
        guard now >= opponentReactAt else { return }
        let oSpeed = levelParams.speed + Double(min(rallyHits, 10)) * 0.08
        let dx = opponentTargetX - opponentX, dz = opponentTargetZ - opponentZ
        let dist = hypot(dx, dz)
        if dist > 1e-3 {
            let step = min(oSpeed * dt, dist)
            opponentX += dx / dist * step
            opponentZ += dz / dist * step
        }
        opponentX = clamp(opponentX, -5.5, 5.5)
        opponentZ = clamp(opponentZ, GameSession.opponentBaseZ - 1.5, -1.2)
    }

    // MARK: - 回合流程

    private func scheduleNextPoint(delay: Double) {
        phase = .countdown(until: now + delay + 1.6)
        ballVisible = true
        contact = nil
        inWindow = false
        currentPath = nil
        pathVersion += 1
        rallyHits = 0
        incomingSummary = ""
        opponentTargetX = Double.random(in: -1.5...1.5)
        opponentTargetZ = GameSession.opponentBaseZ
        opponentX = opponentTargetX
        opponentZ = GameSession.opponentBaseZ
        opponentReactAt = 0
        playerTargetX = 0
        playerTargetZ = GameSession.playerBaseZ
        ball = BallState(position: SIMD3(opponentX, 1.2, GameSession.opponentBaseZ + 0.4), velocity: .zero)
        court.hidePath()
    }

    private func opponentServes() {
        ball = BallState(position: SIMD3(opponentX + 0.3, 1.7, GameSession.opponentBaseZ + 0.5), velocity: .zero)
        launchOpponentShot(zRange: 4.0...8.5, serve: true)
        setMessage("Opponent serves", good: true, duration: 1.0)
        phase = .rally
    }

    private func opponentReturns() {
        // 低等级时对手容易失误，玩家回的拍数越多失误率越高
        let lp = levelParams
        let errorChance = min(lp.errorBase + lp.errorPerHit * Double(rallyHits), 0.9)
        if Double.random(in: 0..<1) < errorChance {
            opponentFaults()
            return
        }
        #if DEBUG
        NSLog(String(format: "[AI] t=%.2f return at opp=(%.1f, %.1f) ball=(%.1f, %.2f, %.1f) bounces=%d", now, opponentX, opponentZ, ball.position.x, ball.position.y, ball.position.z, ball.bounces))
        #endif
        launchOpponentShot(zRange: 4.5...10.5, serve: false)
        court.animateOpponentSwing()
    }

    /// 对手失误：一半打长出界，一半下网。
    private func opponentFaults() {
        court.animateOpponentSwing()
        let p = ball.position
        if Bool.random() {
            let target = SIMD3(Double.random(in: -2...2), 0, Court.halfLength + Double.random(in: 0.8...2.5))
            ball.velocity = ShotSolver.aim(from: p, to: target, speed: 22)
        } else {
            // 下网：够快但太平，正好撞在网带上
            let hr = atan2(Double.random(in: -1.5...1.5) - p.x, -p.z)
            let er = deg2rad(Double.random(in: 1.5 ... 4))
            ball.velocity = 24 * SIMD3(sin(hr) * cos(er), sin(er), cos(hr) * cos(er))
        }
        ball.bounces = 0
        ball.hitNet = false
        ball.lastBounce = nil
        lastHitBy = .opponent
        landingChecked = false
        opponentAttempted = false
        windowHapticDone = false
        history.removeAll()
        opponentTargetX = opponentX
        opponentTargetZ = opponentZ
        pendingSwing = nil
        contact = nil
        #if DEBUG
        autoSwingDone = false
        #endif
        let pred = BallPhysics.predict(from: ball)
        currentPath = pred
        currentPathOwner = .opponent
        pathVersion += 1
        if let c = GameSession.findContact(from: ball) {
            contact = (now + c.time, c.state)
            playerTargetX = c.state.position.x - GameSession.racketX
            playerTargetZ = c.state.position.z + GameSession.hitOffset
        }
        incomingSummary = String(format: "Incoming  %.0f m/s  heading %+.0f°  elevation %+.0f°%@",
                                 ball.speed, ball.headingDegrees, ball.elevationDegrees, pred.inBounds ? "" : "  OUT")
        court.showPath(pred, color: UIColor(white: 1, alpha: 0.85))
    }

    private func launchOpponentShot(zRange: ClosedRange<Double>, serve: Bool) {
        let shot = OpponentAI.returnShot(from: ball.position, difficulty: serve ? 0 : min(rallyHits, levelParams.maxDifficulty), zRange: zRange)
        ball.velocity = shot.velocity
        ball.bounces = 0
        ball.hitNet = false
        ball.lastBounce = nil
        lastHitBy = .opponent
        landingChecked = false
        opponentAttempted = false
        windowHapticDone = false
        history.removeAll()
        opponentTargetX = opponentX          // 击球后站在原地，不回中
        opponentTargetZ = opponentZ
        #if DEBUG
        autoSwingDone = false
        #endif

        let pred = BallPhysics.predict(from: ball)
        currentPath = pred
        currentPathOwner = .opponent
        pathVersion += 1
        pendingSwing = nil
        if let c = GameSession.findContact(from: ball) {
            contact = (now + c.time, c.state)
            playerTargetX = c.state.position.x - GameSession.racketX   // 让球正好飞到球拍上
            playerTargetZ = c.state.position.z + GameSession.hitOffset  // 短球就往前冲
        } else {
            contact = nil
        }
        incomingSummary = String(format: "Incoming  %.0f m/s  heading %+.0f°  elevation %+.0f°  lands x %+.1fm, %.1fm past net%@",
                                 ball.speed, ball.headingDegrees, ball.elevationDegrees,
                                 pred.firstBounce?.x ?? 0, abs(pred.firstBounce?.z ?? 0),
                                 pred.inBounds ? "" : "  OUT")
        court.showPath(pred, color: UIColor(white: 1, alpha: 0.85))
    }

    private func endPoint(winner: Side, text: String) {
        #if DEBUG
        NSLog(String(format: "[END] t=%.2f %@ ball=(%.1f, %.2f, %.1f) bounces=%d", now, text, ball.position.x, ball.position.y, ball.position.z, ball.bounces))
        #endif
        let gameWon = match.award(winner, rallyLength: rallyHits)
        var msg = text
        if gameWon {
            if winner == .player {
                msg += "  🎾 You won the game!"
                if level < GameSession.maxLevel {
                    level += 1
                    msg += "  Level \(level)!"
                }
            } else {
                msg += "  Opponent took the game"
            }
        }
        setMessage(msg, good: winner == .player, duration: 2.4)
        resultHaptic.notificationOccurred(winner == .player ? .success : .error)
        phase = .pointOver(until: now + 2.4)
        contact = nil
        pendingSwing = nil
        inWindow = false
    }

    private func setMessage(_ text: String, good: Bool, duration: Double) {
        message = text
        messageIsGood = good
        messageUntil = now + duration
    }

    // MARK: - 来球触点

    /// 来球在哪里、什么时候可以被玩家打到。
    /// 优先取球穿过底线击球平面的时刻；球到不了那里（短球两跳）就取第一次反弹后的最高点，玩家跑上去接。
    static func findContact(from start: BallState) -> (time: Double, state: BallState)? {
        var s = start
        let dt = 1.0 / 240
        var t = 0.0
        let plane = playerBaseZ - hitOffset
        var apex: (Double, BallState)?
        var prevVy = s.velocity.y
        while t < 5 {
            step(&s, dt: dt)
            t += dt
            if s.hitNet || abs(s.position.z) > 22 { return nil }
            if s.position.z >= plane && s.bounces <= 1 { return (t, s) }
            if s.bounces == 1, s.position.z > 1.0, prevVy > 0, s.velocity.y <= 0, apex == nil {
                apex = (t, s)
            }
            if s.bounces >= 2 { break }
            prevVy = s.velocity.y
        }
        return apex
    }

    private static func step(_ s: inout BallState, dt: Double) { BallPhysics.step(&s, dt: dt) }

    // MARK: - 玩家挥拍判定

    private func handleSwing(_ swing: SwingEvent) {
        if userPaused { return }
        court.flashRacket()
        guard case .rally = phase, lastHitBy == .opponent, let c = contact else {
            if isPlaying {
                lastSwingFeedback = "No ball coming right now"
                lastSwingTiming = "—"
                lastSwingResult = "No ball coming"
            }
            return
        }
        let tSwing = swing.timestamp - latencyCompensation
        let e = c.time - tSwing          // 正数 = 提前，负数 = 晚了
        let window = GameSession.timingWindow

        if e > window + GameSession.earlyBuffer {
            lastSwingFeedback = String(format: "Too early (%.2fs), wait for the ball", e)
            lastSwingTiming = String(format: "%.2fs early", e)
            lastSwingResult = "Too early, missed"
            coachLesson = "Too early: wait until the ball is inside the yellow ring."
            setMessage("Too early", good: false, duration: 0.8)
            return
        }
        if e > window {
            // 稍早：记住这次挥拍，球到了自动打出去（质量打折）
            pendingSwing = swing
            lastSwingFeedback = String(format: "%.2fs early, waiting for the ball…", e)
            lastSwingTiming = String(format: "%.2fs early", e)
            lastSwingResult = "Early, waiting for the ball…"
            return
        }
        if e < -window {
            lastSwingFeedback = String(format: "Too late (%.2fs)", -e)
            lastSwingTiming = String(format: "%.2fs late", -e)
            lastSwingResult = "Too late, missed"
            coachLesson = "Too late: start swinging the moment SWING! appears."
            setMessage("Too late", good: false, duration: 0.8)
            return
        }
        resolveSwing(swing, timingError: e)
    }

    /// 真正把球打出去。timingError 已经在窗口内。
    private func resolveSwing(_ swing: SwingEvent, timingError e: Double) {
        guard case .rally = phase, lastHitBy == .opponent, let c = contact else { return }
        let window = GameSession.timingWindow
        let cp = c.state.position
        let racketWorldX = playerX + GameSession.racketX
        let dx = cp.x - racketWorldX
        let dz = cp.z - hitPlaneZ
        lastSwingTiming = String(format: "%.2fs %@ %@", abs(e), e >= 0 ? "early" : "late", abs(e) < 0.15 ? "✓" : "")
        if abs(dx) > GameSession.playerReach || abs(dz) > 1.2 {
            lastSwingFeedback = String(format: "Out of reach, ball is %.1fm away", hypot(dx, dz))
            lastSwingResult = "Out of reach"
            coachLesson = "Out of reach: that was a winner. Keep the opponent moving with your own placement."
            setMessage("Out of reach", good: false, duration: 0.8)
            return
        }
        if cp.y > 2.5 {
            lastSwingFeedback = "Ball too high"
            lastSwingResult = "Ball too high"
            setMessage("Too high", good: false, duration: 0.8)
            return
        }

        // 击中。按“拍面 × 力度 × 时机”查招式表，只有合适的组合才能过网、不打偏。
        let profile = SwingProfile.shared
        let h = swing.headingDegrees
        let direction = profile.direction(h)
        let hs = swing.handSpeed
        let power = profile.power(hs)
        let el = swing.elevationDegrees
        let face = profile.face(el)
        let goodTiming = abs(e) < 0.15
        let tq = abs(e) / window

        var label = ""
        var depth = 7.5, speed = 20.0
        var highArc = false
        var closedFace = false     // 直接下网
        var failText: String? = nil
        switch (face, power) {
        case ("Closed", _):
            label = "Closed face"; closedFace = true; speed = 18
            failText = "Face too closed, into the net… keep the face from pointing down"
        case ("Flat", "Light"):
            // 不算失误，但是个软而短的弱球，对手很容易上来打
            label = "Soft ball"; depth = 5; speed = 13
        case ("Flat", _):
            label = "Power drive"; depth = goodTiming ? 10.0 : 13.0; speed = 28
            if !goodTiming { failText = "Power drive mistimed, went long" }
        case ("Topspin", "Light"):
            label = "Drop shot"; depth = goodTiming ? 2.5 : 4.5; speed = 12; highArc = true
        case ("Topspin", _):
            label = "Rally ball"; depth = 8.5; speed = 22
        case ("Open", "Light"):
            label = "Lob"; depth = 9; speed = 16; highArc = true
        default:
            label = "Lob"; depth = goodTiming ? 10.5 : 13.0; speed = 19; highArc = true
            if !goodTiming { failText = "Lob too deep, went out" }
        }
        // 方向：重击贴线（赢面大但容易偏）；提前把落点稍往左拉、晚了稍往右推（最多约 0.6m，不改变左中右）
        let baseX: Double = direction == "Center" ? 0 : (power == "Heavy" ? 3.2 : 2.4) * (direction == "Left" ? -1 : 1)
        let tx = baseX - e * 1.4
        if failText == nil && abs(tx) > Court.halfWidthSingles {
            failText = e > 0 ? "Hit early, went wide" : "Hit late, went wide"
        }
        speed *= 1 - 0.1 * tq

        let start = SIMD3(cp.x, max(cp.y, 0.35), cp.z)
        let v: SIMD3<Double>
        if closedFace {
            let er = deg2rad(-4)
            let hr = atan2(tx - start.x, depth + start.z)
            v = speed * SIMD3(sin(hr) * cos(er), sin(er), -cos(hr) * cos(er))
        } else {
            v = ShotSolver.aim(from: start, to: SIMD3(tx, 0, -depth), speed: speed, highArc: highArc)
        }

        let heading = h
        let elevation = el

        ball = BallState(position: SIMD3(cp.x, max(cp.y, 0.35), cp.z), velocity: v)
        if label == "Drop shot" {                                  // 下旋：落地不往前窜、弹不高
            ball.bounceFriction = 0.35
            ball.bounceRestitution = 0.45
        }
        lastHitBy = .player
        landingChecked = false
        opponentAttempted = false
        contact = nil
        inWindow = false
        rallyHits += 1
        history.removeAll()

        let pred = BallPhysics.predict(from: ball)
        #if DEBUG
        NSLog(String(format: "[HIT] t=%.2f %@ from (%.1f, %.2f, %.1f) v=(%.1f, %.1f, %.1f) landing=(%.1f, %.1f) opp=(%.1f, %.1f)", now, label, start.x, start.y, start.z, v.x, v.y, v.z, pred.firstBounce?.x ?? 0, pred.firstBounce?.z ?? 0, opponentX, opponentZ))
        #endif
        currentPath = pred
        currentPathOwner = .player
        pathVersion += 1
        if let b = pred.firstBounce {
            // 跑到落点后方 1.5m 处；吊球就得往前冲
            opponentTargetX = b.x
            opponentTargetZ = clamp(b.z - 1.5, GameSession.opponentBaseZ, -1.5)
        } else if let z = pred.points.first(where: { $0.z <= opponentZ + 1.0 }) {
            opponentTargetX = z.x
        }
        opponentReactAt = now + levelParams.reaction
        let info = ShotInfo(direction: direction, power: power, handSpeed: hs,
                            faceHeading: swing.faceHeadingDegrees, pathHeading: swing.pathHeadingDegrees,
                            faceElevation: swing.faceElevationDegrees, pathElevation: swing.pathElevationDegrees, face: "\(face)·\(label)",
                            headingDegrees: heading, elevationDegrees: elevation, speed: speed, timingError: e,
                            netClearance: pred.netClearance, landing: pred.firstBounce,
                            inBounds: pred.inBounds, hitNet: pred.hitNet)
        lastShot = info
        lastSwingFeedback = info.summary
        switch label {
        case "Closed face": coachLesson = String(format: "Chopped down → net. Keep the swing tilt above %+.0f°.", profile.closedTilt)
        case "Soft ball": coachLesson = String(format: "Light flat swing = soft ball. Swing harder (> %.1f m/s), or lift a bit for a drop shot.", profile.heavySpeed)
        case "Power drive": coachLesson = goodTiming ? "Power drive in! Flat + heavy needs timing within ±0.15s." : "Heavy flat shot mistimed → long. Topspin is the safer heavy shot."
        case "Drop shot": coachLesson = goodTiming ? "Nice drop shot. Best when the opponent is on the baseline." : "Drop shot mistimed → deeper. Perfect timing makes it die at the net."
        case "Rally ball": coachLesson = "Safe rally ball. Now look where the opponent is and aim the other way."
        case "Lob": coachLesson = failText == nil ? "Lob in. Great when the opponent is at the net." : "Heavy lob went long. Use a lighter swing for lobs."
        default: break
        }
        if failText != nil, failText!.contains("wide") { coachLesson = "Timing error pushed the ball wide. Aim center when timing feels off." }
        if let failText {
            lastSwingResult = "\(label) → \(failText)"
        } else if !pred.crossedNet {
            lastSwingResult = "\(label) → did not clear the net"
        } else {
            lastSwingResult = String(format: "%@ → %@, lands %@ (%.1fm past net)", label, pred.inBounds ? "over the net" : "over the net", pred.inBounds ? "IN" : "OUT", abs(pred.firstBounce?.z ?? 0))
        }
        incomingSummary = ""
        let pathColor = pred.hitNet || !pred.inBounds ? UIColor.systemRed : UIColor.systemCyan
        court.showPath(pred, color: pathColor)
        court.animateRacketHit(toLocal: SIMD3(cp.x - playerX, max(cp.y, 0.35), cp.z - playerZ))
        hitHaptic.impactOccurred()

        if let failText {
            setMessage(failText, good: false, duration: 1.4)
        } else if !pred.crossedNet {
            setMessage(pred.hitNet ? "Going into the net…" : "Landed before the net…", good: false, duration: 1.2)
        } else if !pred.inBounds {
            setMessage("Going out…", good: false, duration: 1.2)
        } else {
            let quip = goodTiming ? "Perfect timing!" : "Got it"
            setMessage("\(quip) \(direction) \(label)", good: true, duration: 1.0)
        }
    }
}

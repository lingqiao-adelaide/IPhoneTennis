import Foundation

/// 每个人的挥拍分界：由校准向导从用户自己的动作样本里学出来，没做向导就用默认值。
struct SwingProfile: Codable {
    var headingBias = 0.0        // 直挥时的原始方向角（之后每拍减掉）
    var leftThreshold = -8.0     // 相对方向角 < 此 → Left
    var rightThreshold = 8.0     // > 此 → Right
    var heavySpeed = 3.6         // 手速 ≥ 此 → Heavy
    var closedTilt = -20.0       // 仰角 < 此 → Closed
    var flatTilt = 8.0           // closed ~ 此 → Flat
    var openTilt = 35.0          // ≥ 此 → Open（中间是 Topspin）
    var isCustom = false

    static let defaultsKey = "swing.profile"

    static var shared: SwingProfile = load() {
        didSet { shared.save() }
    }

    static func load() -> SwingProfile {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let p = try? JSONDecoder().decode(SwingProfile.self, from: data) {
            return p
        }
        return SwingProfile()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: SwingProfile.defaultsKey)
        }
    }

    func direction(_ heading: Double) -> String {
        heading < leftThreshold ? "Left" : (heading > rightThreshold ? "Right" : "Center")
    }

    func power(_ handSpeed: Double) -> String {
        handSpeed < heavySpeed ? "Light" : "Heavy"
    }

    func face(_ tilt: Double) -> String {
        tilt < closedTilt ? "Closed" : (tilt < flatTilt ? "Flat" : (tilt < openTilt ? "Topspin" : "Open"))
    }

    var summary: String {
        String(format: "center %+.0f° · left < %+.0f° · right > %+.0f° · heavy ≥ %.1f m/s · closed < %+.0f° · flat < %+.0f° · open ≥ %+.0f°",
               headingBias, leftThreshold, rightThreshold, heavySpeed, closedTilt, flatTilt, openTilt)
    }

    /// 从向导采到的样本构建档案。样本里的 heading 是未减零点的原始值。
    static func build(straight: [SwingEvent], left: [SwingEvent], right: [SwingEvent],
                      soft: [SwingEvent], hard: [SwingEvent], chop: [SwingEvent], lift: [SwingEvent]) -> SwingProfile {
        func mean(_ xs: [Double], fallback: Double) -> Double { xs.isEmpty ? fallback : xs.reduce(0, +) / Double(xs.count) }
        var p = SwingProfile()
        let center = mean(straight.map { $0.headingDegrees }, fallback: 0)
        p.headingBias = clamp(center, -40, 40)
        let l = mean(left.map { $0.headingDegrees }, fallback: center - 30) - center
        let r = mean(right.map { $0.headingDegrees }, fallback: center + 30) - center
        // 分界放在“直挥”和“左/右”的中点，至少离零点 5°
        p.leftThreshold = min(l * 0.5, -5)
        p.rightThreshold = max(r * 0.5, 5)

        let sSoft = mean(soft.map { $0.handSpeed }, fallback: 2.0)
        let sHard = mean(hard.map { $0.handSpeed }, fallback: 5.5)
        p.heavySpeed = clamp((sSoft + sHard) / 2, 1.5, 8)

        let tNormal = mean(straight.map { $0.elevationDegrees }, fallback: 15)
        let tChop = mean(chop.map { $0.elevationDegrees }, fallback: tNormal - 40)
        let tLift = mean(lift.map { $0.elevationDegrees }, fallback: tNormal + 35)
        let down = max(tNormal - tChop, 10)
        let up = max(tLift - tNormal, 10)
        // 正常挥拍落在 Topspin 区；比正常再平一点是 Flat；砍下去是 Closed；挑起来是 Open
        p.closedTilt = tNormal - down * 0.6
        p.flatTilt = tNormal - down * 0.25
        p.openTilt = tNormal + up * 0.55
        p.isCustom = true
        return p
    }
}

import Foundation
import simd

/// 给定落点和球速，反推出能落到那里的出球方向（双方共用）。
enum ShotSolver {
    /// - highArc: true 时在能落到目标的解里选弧线最高的（高吊），否则选最低且过网有余量的（平击）。
    static func aim(from p: SIMD3<Double>, to target: SIMD3<Double>, speed: Double, highArc: Bool = false) -> SIMD3<Double> {
        // 给定球速到不了目标（比如贴地的低球要吊过网）就逐步加速，保证总有一条可行轨迹
        var best: (err: Double, v: SIMD3<Double>)?
        for extra in stride(from: 0.0, through: 12.0, by: 2.0) {
            let r = aimOnce(from: p, to: target, speed: speed + extra, highArc: highArc)
            if r.good { return r.v }
            if best == nil || r.err < best!.err { best = (r.err, r.v) }
        }
        return best!.v
    }

    private static func aimOnce(from p: SIMD3<Double>, to target: SIMD3<Double>, speed: Double, highArc: Bool) -> (v: SIMD3<Double>, good: Bool, err: Double) {
        let dirZ = target.z - p.z >= 0 ? 1.0 : -1.0
        var best: (err: Double, v: SIMD3<Double>)?
        let dx = target.x - p.x, dz = target.z - p.z
        let len = max(hypot(dx, dz), 1e-6)
        // 平击从低仰角往上找、高吊从高往下找，碰到第一条可行轨迹就停，省掉大部分模拟
        let degrees: [Double] = highArc ? Array(stride(from: 48.0, through: -4.0, by: -2.0))
                                        : Array(stride(from: -4.0, through: 48.0, by: 2.0))
        for deg in degrees {
            let el = deg2rad(deg)
            let horiz = cos(el)
            let v = speed * SIMD3(dx / len * horiz, sin(el), dz / len * horiz)
            let land = BallPhysics.landing(from: BallState(position: p, velocity: v))
            guard let b = land.firstBounce else { continue }
            let err = hypot(b.x - target.x, b.z - target.z)
            if !land.hitNet, land.crossedNet, land.netClearance > 0.15, err < 0.7 {
                return (v, true, err)
            }
            if best == nil || err < best!.err { best = (err, v) }
        }
        return (best?.v ?? speed * SIMD3(0, 0.3, dirZ), false, best?.err ?? 99)
    }
}

/// 电脑对手：选一个落点，用给定球速反推出能落到那里的出球仰角。
enum OpponentAI {
    struct Shot {
        var velocity: SIMD3<Double>
        var target: SIMD3<Double>
    }

    /// - difficulty: 当前回合数，越大球越快、落点越刁钻、偶尔也会失误。
    static func returnShot(from p: SIMD3<Double>, difficulty: Int, zRange: ClosedRange<Double>) -> Shot {
        let d = Double(min(difficulty, 12))
        let spread = min(1.2 + d * 0.3, 3.7)
        let tx = Double.random(in: -spread...spread)
        let tz = Double.random(in: zRange)
        let speed = min(16.0 + d * 1.1, 30.0) + Double.random(in: 0...2)
        var v = ShotSolver.aim(from: p, to: SIMD3(tx, 0, tz), speed: speed)
        // 随难度增加的人为误差：难度高时对手也会打出界/下网
        let noise = deg2rad(Double.random(in: -1...1) * min(0.6 + d * 0.25, 3.0))
        let h = hypot(v.x, v.z)
        let el = atan2(v.y, h) + noise
        let heading = atan2(v.x, v.z)
        let sp = simd_length(v)
        v = sp * SIMD3(sin(heading) * cos(el), sin(el), cos(heading) * cos(el))
        return Shot(velocity: v, target: SIMD3(tx, 0, tz))
    }
}

import Foundation
import simd

/// 球场尺寸（米）。坐标系：x 左右，y 向上，z 前后。玩家在 +z 端，对手在 -z 端，网在 z = 0。
enum Court {
    static let halfLength = 11.885
    static let halfWidthSingles = 4.115
    static let halfWidthDoubles = 5.485
    static let serviceLineZ = 6.40
    static let netHeightCenter = 0.914
    static let netHeightPost = 1.07

    /// 网在 x 处的高度（中间低、两边高）。
    static func netHeight(atX x: Double) -> Double {
        let t = min(abs(x) / halfWidthDoubles, 1.0)
        return netHeightCenter + (netHeightPost - netHeightCenter) * t
    }

    static func isInside(x: Double, z: Double) -> Bool {
        abs(x) <= halfWidthSingles + 0.03 && abs(z) <= halfLength + 0.03
    }
}

struct BallState {
    var position: SIMD3<Double>
    var velocity: SIMD3<Double>
    var bounces = 0
    var hitNet = false
    var lastBounce: SIMD3<Double>?
    /// 落地后保留的横向速度比例：普通球 0.8，带下旋的吊球约 0.35（落地就“死”）
    var bounceFriction = BallPhysics.groundFriction
    /// 落地反弹系数：普通球 0.72，下旋吊球约 0.45（弹不高）
    var bounceRestitution = BallPhysics.restitution

    var speed: Double { simd_length(velocity) }

    /// 水平方向角（度）：从玩家视角看，球偏向右边为正、左边为负。
    var headingDegrees: Double {
        atan2(velocity.x, abs(velocity.z)) * 180 / .pi
    }

    /// 仰角（度）：速度与水平面的夹角。
    var elevationDegrees: Double {
        let h = hypot(velocity.x, velocity.z)
        return atan2(velocity.y, h) * 180 / .pi
    }
}

enum BallPhysics {
    static let gravity = 9.81
    static let drag = 0.018          // 空气阻力 a = -k·|v|·v（接近真实网球）
    static let restitution = 0.72    // 落地反弹系数
    static let groundFriction = 0.80 // 落地后水平速度保留比例
    static let radius = 0.033

    static func step(_ s: inout BallState, dt: Double) {
        let v = s.velocity
        var acc = SIMD3<Double>(0, -gravity, 0)
        acc -= drag * simd_length(v) * v
        let newV = v + acc * dt
        var newP = s.position + newV * dt

        // 过网检测：这一帧是否跨越 z = 0 平面，跨越点是否低于网。
        let z0 = s.position.z, z1 = newP.z
        if (z0 > 0 && z1 <= 0) || (z0 < 0 && z1 >= 0) {
            let t = z0 / (z0 - z1)
            let xAtNet = s.position.x + (newP.x - s.position.x) * t
            let yAtNet = s.position.y + (newP.y - s.position.y) * t
            if yAtNet - radius < Court.netHeight(atX: xAtNet) && abs(xAtNet) < Court.halfWidthDoubles + 0.9 {
                s.hitNet = true
                // 球撞网后掉回自己这一边
                let side = z0 > 0 ? 1.0 : -1.0
                s.position = SIMD3(xAtNet, yAtNet, side * 0.06)
                s.velocity = SIMD3(newV.x * 0.15, min(newV.y, 0) * 0.2, side * abs(newV.z) * 0.08)
                return
            }
        }

        if newP.y - radius <= 0 && newV.y < 0 {
            newP.y = radius
            s.bounces += 1
            s.lastBounce = newP
            var bounced = SIMD3(newV.x * s.bounceFriction, -newV.y * s.bounceRestitution, newV.z * s.bounceFriction)
            if bounced.y < 0.4 {
                bounced.y = 0
                s.bounces += 1      // 弹不起来的死球算作再跳一次，免得滚着滚着被接到
            }
            s.velocity = bounced
        } else {
            s.velocity = newV
        }
        s.position = newP
    }

    struct Prediction {
        var points: [SIMD3<Double>]       // 用来画轨迹的采样点
        var firstBounce: SIMD3<Double>?    // 第一落点
        var hitNet: Bool
        var netClearance: Double?          // 过网时球心高于网带的距离（负数表示理论上会撞网）
        var crossedNet: Bool
        /// 界内 = 过了网并且第一落点在单打场地内。没过网就落地的球算失误。
        var inBounds: Bool { crossedNet && (firstBounce.map { Court.isInside(x: $0.x, z: $0.z) } ?? false) }
    }

    /// 向前模拟整条轨迹（不改变传入状态）。
    static func predict(from start: BallState, maxTime: Double = 5, stopAfterBounces: Int = 2) -> Prediction {
        var s = start
        s.bounces = 0
        s.hitNet = false
        s.lastBounce = nil
        let dt = 1.0 / 240
        var points = [s.position]
        var firstBounce: SIMD3<Double>?
        var clearance: Double?
        var crossed = false
        let startSide = s.position.z > 0
        var t = 0.0, sinceSample = 0.0
        while t < maxTime {
            let prevZ = s.position.z
            step(&s, dt: dt)
            t += dt
            sinceSample += dt
            // 还没过网就落在自己半场：这一分已经结束，不再往后算
            if !crossed, s.bounces >= 1, (s.position.z > 0) == startSide {
                firstBounce = s.lastBounce
                points.append(s.position)
                break
            }
            if !crossed && !s.hitNet && (prevZ > 0) != (s.position.z > 0) {
                crossed = true
                clearance = s.position.y - Court.netHeight(atX: s.position.x)
            }
            if sinceSample >= 0.045 {
                points.append(s.position)
                sinceSample = 0
            }
            if firstBounce == nil, s.bounces >= 1 { firstBounce = s.lastBounce }
            if s.hitNet || s.bounces >= stopAfterBounces { break }
            if abs(s.position.z) > 22 || abs(s.position.x) > 16 { break }
        }
        points.append(s.position)
        return Prediction(points: points, firstBounce: firstBounce, hitNet: s.hitNet, netClearance: clearance, crossedNet: crossed)
    }

    /// 轻量版轨迹模拟：只算落点、是否过网、过网高度，不收集采样点（求解器用，调用次数多）。
    struct Landing {
        var firstBounce: SIMD3<Double>?
        var hitNet: Bool
        var crossedNet: Bool
        var netClearance: Double
    }

    static func landing(from start: BallState, dt: Double = 1.0 / 120, maxTime: Double = 4) -> Landing {
        var s = start
        s.bounces = 0
        s.hitNet = false
        s.lastBounce = nil
        let startSide = s.position.z > 0
        var crossed = false
        var clearance = 0.0
        var t = 0.0
        while t < maxTime {
            let prevZ = s.position.z
            step(&s, dt: dt)
            t += dt
            if !crossed && !s.hitNet && (prevZ > 0) != (s.position.z > 0) {
                crossed = true
                clearance = s.position.y - Court.netHeight(atX: s.position.x)
            }
            if s.hitNet { break }
            if s.bounces >= 1 {
                if !crossed && (s.position.z > 0) == startSide { return Landing(firstBounce: s.lastBounce, hitNet: false, crossedNet: false, netClearance: 0) }
                break
            }
            if abs(s.position.z) > 22 || abs(s.position.x) > 16 { break }
        }
        return Landing(firstBounce: s.lastBounce, hitNet: s.hitNet, crossedNet: crossed, netClearance: clearance)
    }

    /// 球到达某个 z 平面需要的时间以及到达时的状态；到不了（撞网、两跳、飞出）返回 nil。
    static func timeToReach(z target: Double, from start: BallState, maxTime: Double = 4) -> (time: Double, state: BallState)? {
        var s = start
        let dt = 1.0 / 240
        var t = 0.0
        let startsBefore = s.position.z < target
        while t < maxTime {
            step(&s, dt: dt)
            t += dt
            let nowBefore = s.position.z < target
            if nowBefore != startsBefore { return (t, s) }
            if s.hitNet || s.bounces >= 2 { return nil }
            if abs(s.position.z) > 22 { return nil }
        }
        return nil
    }
}

@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
@inline(__always) func deg2rad(_ d: Double) -> Double { d * .pi / 180 }
@inline(__always) func rad2deg(_ r: Double) -> Double { r * 180 / .pi }

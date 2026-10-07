import Foundation
import CoreMotion
import simd

/// 一次挥拍事件。角度都是相对于“校准时指向电视的方向”。
struct SwingEvent {
    let timestamp: TimeInterval     // 与 ProcessInfo.systemUptime 同一时间基准
    var headingDegrees: Double      // 水平方向：右正左负（拍面与路径的综合，已减零点）
    let elevationDegrees: Double    // 拍面仰角：正数球往上走
    let handSpeed: Double           // 手的峰值速度 m/s
    var faceHeadingDegrees: Double = 0   // 分量：拍面朝向
    var pathHeadingDegrees: Double = 0   // 分量：挥动路径方向
    var faceElevationDegrees: Double = 0 // 分量：拍面（屏幕法线）倾角
    var pathElevationDegrees: Double = 0 // 分量：挥动路径倾角
}

/// 实时的拍面姿态，用于 HUD 和 3D 球拍模型。
struct RacketPose {
    var elevationDegrees = 0.0
    var headingDegrees = 0.0
    /// 手机顶端指向哪里（相对校准方向，右正左负），校准页用它画箭头。
    var pointingDegrees = 0.0
    /// 已经静止了多久（秒），校准会话用它自动对正。
    var stillSeconds = 0.0
    /// 手机的 x/y/z 轴在游戏场景坐标系中的方向（场景：x 右，y 上，z 朝向玩家身后）。
    var axesInScene: (x: SIMD3<Double>, y: SIMD3<Double>, z: SIMD3<Double>)?
}

/// 把 iPhone 当网球拍：屏幕 = 拍面，手机顶端 = 拍头方向。
///
/// 检测思路：
/// 1. 用 userAcceleration（已去掉重力）在参考系中积分得到手的速度；
/// 2. 加速度/角速度超过阈值进入“挥拍中”，安静一小段时间后结束；
/// 3. 速度峰值时刻 = 击球时刻，取该时刻的拍面法线和速度方向算出方向角与仰角。
final class SwingDetector {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "SwingDetector"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    /// 在主线程回调
    var onSwing: ((SwingEvent) -> Void)?

    private(set) var isAvailable = false
    private(set) var live = RacketPose()
    private var isSwinging = false
    private(set) var isCalibrated = false
    /// 方向零点（来自个人档案），每一拍的方向角减掉它。
    var headingBias: Double = SwingProfile.shared.headingBias {
        didSet { let b = headingBias; queue.addOperation { [self] in biasOnQueue = b } }
    }
    private var biasOnQueue: Double = SwingProfile.shared.headingBias

    /// 校准向导用：采集接下来 count 次挥拍，完成后在主线程回调。
    private var capture: (remaining: Int, samples: [SwingEvent], completion: ([SwingEvent]) -> Void)?
    private(set) var captureRemaining = 0

    func captureSwings(count: Int, completion: @escaping ([SwingEvent]) -> Void) {
        captureRemaining = count
        queue.addOperation { [self] in capture = (count, [], completion) }
    }

    func cancelCapture() {
        captureRemaining = 0
        queue.addOperation { [self] in capture = nil }
    }

    /// 左右镜像（保险开关，校准页可切换，会记住）。
    var mirrored: Bool = UserDefaults.standard.bool(forKey: "swing.mirrored") {
        didSet { UserDefaults.standard.set(mirrored, forKey: "swing.mirrored") }
    }
    /// 最近一次识别到的挥拍，校准页的“挥拍自检”用。
    private(set) var lastSwing: SwingEvent?

    // 参考系里“指向电视”的水平单位向量（参考系：z 轴竖直向上）
    private var forward = SIMD3<Double>(0, 1, 0)
    private var lastQ: simd_quatd?
    private var lastTimestamp: TimeInterval?

    // 挥拍过程中的积分状态
    private var swingStart = 0.0
    private var velocity = SIMD3<Double>.zero
    private var peakSpeed = 0.0
    private var peakVelocity = SIMD3<Double>.zero
    private var peakNormal = SIMD3<Double>.zero       // 屏幕法线（z 轴）
    private var peakSideNormal = SIMD3<Double>.zero   // 侧边法线（x 轴）
    private var peakTime = 0.0
    private var quietSince: TimeInterval?
    private var lastSwingEnd = 0.0
    private var emitted = false
    private var pendingPose = RacketPose()
    private var poseDispatchScheduled = false
    private var lastMotionTime: TimeInterval = 0

    // 阈值
    private let startAccel = 7.0       // m/s²：早一点开始积分，手速才不会算小
    private let startRotation = 4.0    // rad/s
    private let quietAccel = 4.0
    private let quietRotation = 2.5
    private let minPeakSpeed = 1.3     // m/s，低于此视为晃动不是挥拍

    func start() {
        guard manager.isDeviceMotionAvailable else {
            isAvailable = false
            return
        }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 100
        // 100 Hz 的传感器处理放在后台队列，主线程只收结果
        manager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    /// 让玩家把手机顶端指向电视后调用：把当前朝向记为“正前方”。
    func calibrateForward() {
        queue.addOperation { [self] in calibrateOnQueue() }
    }

    private func calibrateOnQueue() {
        guard let q = lastQ else { return }
        var f = q.act(SIMD3(0, 1, 0))          // 手机顶端方向
        f.z = 0
        if simd_length(f) < 0.3 {              // 手机竖着拿时顶端朝天，改用背面方向
            f = q.act(SIMD3(0, 0, -1))
            f.z = 0
        }
        if simd_length(f) > 0.05 {
            forward = simd_normalize(f)
            DispatchQueue.main.async { self.isCalibrated = true }
        }
    }

    /// 没有传感器（模拟器）或测试时注入一次挥拍。
    func injectSwing(heading: Double, elevation: Double, handSpeed: Double) {
        let event = SwingEvent(timestamp: ProcessInfo.processInfo.systemUptime,
                               headingDegrees: heading, elevationDegrees: elevation, handSpeed: handSpeed)
        lastSwing = event
        onSwing?(event)
    }

    // MARK: - 内部

    private func process(_ m: CMDeviceMotion) {
        let t = m.timestamp
        let dt = lastTimestamp.map { min(t - $0, 0.05) } ?? 0.01
        lastTimestamp = t
        let q = simd_quatd(ix: m.attitude.quaternion.x, iy: m.attitude.quaternion.y,
                           iz: m.attitude.quaternion.z, r: m.attitude.quaternion.w)
        lastQ = q

        let aDevice = SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z) * 9.81
        let aRef = q.act(aDevice)
        let aMag = simd_length(aRef)
        let rot = simd_length(SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z))
        let normal = q.act(SIMD3(0, 0, 1))   // 屏幕法线在参考系中的方向
        let sideNormal = q.act(SIMD3(1, 0, 0)) // 侧边法线：屏幕朝侧面握持时真正迎球的是侧边

        if aMag > 1.2 || rot > 0.35 { lastMotionTime = t }
        updateLivePose(q: q, normal: normal, stillSeconds: lastMotionTime == 0 ? 0 : t - lastMotionTime)

        if !isSwinging {
            if (aMag > startAccel || rot > startRotation) && t - lastSwingEnd > 0.35 {
                isSwinging = true
                swingStart = t
                velocity = .zero
                peakSpeed = 0
                peakTime = t
                quietSince = nil
                emitted = false
            }
        }
        guard isSwinging else { return }

        velocity += aRef * dt
        let sp = simd_length(velocity)
        if sp > peakSpeed {
            peakSpeed = sp
            peakVelocity = velocity
            peakNormal = normal
            peakSideNormal = sideNormal
            peakTime = t
        }
        // 速度一过峰值就立刻发出击球事件，不等随挥结束，否则球早就飞过去了。
        if !emitted && peakSpeed >= minPeakSpeed && (sp < peakSpeed * 0.8 || t - peakTime > 0.12) {
            emitted = true
            emit()
        }
        let quiet = aMag < quietAccel && rot < quietRotation
        if quiet {
            if quietSince == nil { quietSince = t }
        } else {
            quietSince = nil
        }
        let ended = (quietSince.map { t - $0 > 0.08 } ?? false) || t - swingStart > 0.8
        if ended {
            isSwinging = false
            lastSwingEnd = t
            if !emitted && peakSpeed >= minPeakSpeed { emit() }
        }
    }

    private func emit() {
        var v = peakVelocity
        // 挥拍永远是朝电视打的。userAcceleration 报的是惯性力方向（与运动方向相反），
        // 直接积分会得到反向速度；这里统一归到“朝前”那一侧，不依赖符号约定。
        if simd_dot(SIMD3(v.x, v.y, 0), forward) < 0 { v = -v }
        // 拍面：屏幕(z)和侧边(x)两个轴里，取与运动方向最一致的那个；正反面也按运动方向定。
        // 这样屏幕朝前、朝左、朝右握持都能正确找到迎球面。
        var n = peakNormal
        var side = peakSideNormal
        if simd_dot(n, v) < 0 { n = -n }
        if simd_dot(side, v) < 0 { side = -side }
        let vn = simd_length(v) > 1e-6 ? simd_normalize(v) : v
        if simd_dot(side, vn) > simd_dot(n, vn) { n = side }

        let vh = SIMD3(v.x, v.y, 0)
        let nh = SIMD3(n.x, n.y, 0)
        let pathHeading = signedHeading(of: vh)
        let pathElevation = rad2deg(atan2(v.z, simd_length(vh)))
        let faceHeading = simd_length(nh) > 0.05 ? signedHeading(of: nh) : pathHeading
        let faceElevation = rad2deg(atan2(n.z, max(simd_length(nh), 1e-6)))

        // 拍面是否正对运动方向：夹角太大（侧着切）时拍面朝向不可信，只看挥动路径
        let alignment = simd_length(nh) > 0.05 && simd_length(vh) > 0.05
            ? simd_dot(simd_normalize(nh), simd_normalize(vh)) : 0
        let faceWeight = alignment < 0.4 ? 0.0 : 0.5
        let rawHeading = faceWeight * faceHeading + (1 - faceWeight) * pathHeading
        // 仰角以挥动路径为主：扣球/上旋主要体现在路径上，拍面做修正
        var elevation = 0.4 * faceElevation + 0.6 * pathElevation
        elevation = clamp(elevation, -20, 70)

        let heading = clamp(rawHeading - biasOnQueue, -60, 60)

        var event = SwingEvent(timestamp: peakTime, headingDegrees: heading,
                               elevationDegrees: elevation, handSpeed: peakSpeed)
        event.faceHeadingDegrees = faceHeading
        event.pathHeadingDegrees = pathHeading
        event.faceElevationDegrees = faceElevation
        event.pathElevationDegrees = pathElevation
        // 向导采样：记录未减零点的原始方向角
        if var c = capture {
            var raw = event
            raw.headingDegrees = clamp(rawHeading, -90, 90)
            c.samples.append(raw)
            c.remaining -= 1
            if c.remaining <= 0 {
                capture = nil
                let samples = c.samples
                DispatchQueue.main.async { self.captureRemaining = 0; c.completion(samples) }
            } else {
                capture = c
                let left = c.remaining
                DispatchQueue.main.async { self.captureRemaining = left }
            }
        }
        DispatchQueue.main.async {
            self.lastSwing = event
            self.onSwing?(event)
        }
    }

    private func updateLivePose(q: simd_quatd, normal: SIMD3<Double>, stillSeconds: Double) {
        var n = normal
        let nh = SIMD3(n.x, n.y, 0)
        // 取朝向电视那一面的法线作为拍面
        if simd_dot(nh, forward) < 0 { n = -n }
        let nh2 = SIMD3(n.x, n.y, 0)
        let elevation = rad2deg(atan2(n.z, max(simd_length(nh2), 1e-6)))
        let heading = simd_length(nh2) > 0.05 ? signedHeading(of: nh2) : 0

        // 手机顶端的指向；竖着拿时顶端朝天，改看背面
        var top = q.act(SIMD3(0, 1, 0))
        top.z = 0
        if simd_length(top) < 0.3 {
            top = q.act(SIMD3(0, 0, -1))
            top.z = 0
        }
        let pointing = simd_length(top) > 0.05 ? signedHeading(of: top) : 0

        let ex = toScene(q.act(SIMD3(1, 0, 0)))
        let ey = toScene(q.act(SIMD3(0, 1, 0)))
        let ez = toScene(q.act(SIMD3(0, 0, 1)))
        let pose = RacketPose(elevationDegrees: elevation, headingDegrees: heading,
                              pointingDegrees: pointing, stillSeconds: stillSeconds, axesInScene: (ex, ey, ez))
        pendingPose = pose
        if !poseDispatchScheduled {
            poseDispatchScheduled = true
            DispatchQueue.main.async {
                self.live = self.pendingPose
                self.poseDispatchScheduled = false
            }
        }
    }

    /// 水平向量相对 forward 的带符号夹角（度），右正左负。
    private func signedHeading(of w: SIMD3<Double>) -> Double {
        let c = simd_cross(forward, w)
        let ccw = atan2(c.z, simd_dot(forward, w))   // 从上往下看逆时针为正 = 向左
        return (mirrored ? 1 : -1) * rad2deg(ccw)
    }

    /// 参考系 → 场景坐标系。场景 x = 右，y = 上，z = 背向电视。
    private func toScene(_ v: SIMD3<Double>) -> SIMD3<Double> {
        let up = SIMD3<Double>(0, 0, 1)
        let right = simd_cross(forward, up)
        return SIMD3((mirrored ? -1 : 1) * simd_dot(v, right), v.z, -simd_dot(v, forward))
    }
}

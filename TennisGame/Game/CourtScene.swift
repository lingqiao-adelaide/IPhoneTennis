import SceneKit
import UIKit
import simd

/// 第一视角 3D 球场。只负责画，不含任何规则。
final class CourtScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    let playerRoot = SCNNode()

    private let racketNode = SCNNode()
    private let racketStrings = SCNMaterial()
    private let hitRing = SCNNode()
    private let hitRingMaterial = SCNMaterial()
    private let ballNode = SCNNode()
    private let ballShadow = SCNNode()
    private let opponentNode = SCNNode()
    private let opponentRacket = SCNNode()
    private let pathRoot = SCNNode()
    private var dots: [SCNNode] = []
    private let dotMaterial = SCNMaterial()
    private let landingMarker = SCNNode()
    private let landingMaterial = SCNMaterial()
    private let netMarker = SCNNode()
    private var shownPathVersion = -1
    private var cullZ = GameSession.playerBaseZ - 0.4
    private var racketFlashUntil = 0.0

    private static let racketOffset = SIMD3<Double>(GameSession.racketX, 1.0, -0.15)
    private var lungeTarget = SIMD3<Double>.zero
    private var lungeStart = -1.0

    init() {
        buildWorld()
        buildCourt()
        buildNet()
        buildBall()
        buildOpponent()
        buildPlayer()
        buildPath()
    }

    // MARK: - 每帧同步

    func update(session: GameSession, time: Double) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0

        let p = session.ball.position
        ballNode.isHidden = !session.ballVisible
        ballShadow.isHidden = !session.ballVisible
        ballNode.position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
        ballShadow.position = SCNVector3(Float(p.x), 0.006, Float(p.z))
        let s = Float(clamp(1.3 - p.y * 0.12, 0.5, 1.3))
        ballShadow.scale = SCNVector3(s, 1, s)

        playerRoot.position.x = Float(session.playerX)
        playerRoot.position.z = Float(session.playerZ)
        cullZ = session.playerZ - 0.4
        opponentNode.position.x = Float(session.opponentX)
        opponentNode.position.z = Float(session.opponentZ)

        if session.inWindow {
            hitRingMaterial.emission.contents = UIColor.yellow
            hitRing.opacity = 1
            let pulse = Float(1 + 0.08 * sin(time * 18))
            hitRing.scale = SCNVector3(pulse, pulse, pulse)
        } else {
            hitRingMaterial.emission.contents = UIColor(white: 0.25, alpha: 1)
            hitRing.opacity = 0.25
            hitRing.scale = SCNVector3(1, 1, 1)
        }

        // 击中后球拍“伸”到触球点再收回（拍头在把手上方 0.25m，所以目标点要往下挪）
        var o = CourtScene.racketOffset
        let since = time - lungeStart
        if lungeStart > 0 && since < 0.35 {
            let f = since < 0.08 ? since / 0.08 : max(0, 1 - (since - 0.08) / 0.27)
            let target = lungeTarget - SIMD3(0, 0.25, 0)
            o = o + (target - o) * f
        }
        if let axes = session.motion.live.axesInScene {
            racketNode.simdTransform = simd_float4x4(columns: (
                SIMD4<Float>(Float(axes.x.x), Float(axes.x.y), Float(axes.x.z), 0),
                SIMD4<Float>(Float(axes.y.x), Float(axes.y.y), Float(axes.y.z), 0),
                SIMD4<Float>(Float(axes.z.x), Float(axes.z.y), Float(axes.z.z), 0),
                SIMD4<Float>(Float(o.x), Float(o.y), Float(o.z), 1)))
        } else {
            racketNode.position = SCNVector3(Float(o.x), Float(o.y), Float(o.z))
        }
        racketStrings.emission.contents = time < racketFlashUntil ? UIColor.systemCyan : UIColor.black

        if session.pathVersion != shownPathVersion, session.currentPath == nil {
            hidePath()
        }
        SCNTransaction.commit()
    }

    func showPath(_ pred: BallPhysics.Prediction, color: UIColor) {
        dotMaterial.diffuse.contents = color
        dotMaterial.emission.contents = color.withAlphaComponent(0.6)
        let pts = pred.points
        let n = dots.count
        let stride = max(1, Int(ceil(Double(pts.count) / Double(n))))
        var i = 0
        var di = 0
        while i < pts.count && di < n {
            let p = pts[i]
            if p.z > cullZ { i += stride; continue }   // 镜头后面的点不画
            dots[di].position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
            dots[di].isHidden = false
            i += stride
            di += 1
        }
        while di < n { dots[di].isHidden = true; di += 1 }

        if let b = pred.firstBounce {
            landingMarker.isHidden = false
            landingMarker.position = SCNVector3(Float(b.x), 0.012, Float(b.z))
            let c: UIColor = pred.inBounds ? .systemGreen : .systemRed
            landingMaterial.diffuse.contents = c
            landingMaterial.emission.contents = c
        } else {
            landingMarker.isHidden = true
        }
        if pred.hitNet {
            netMarker.isHidden = false
            netMarker.position = SCNVector3(Float(pts.last?.x ?? 0), 0.9, 0)
        } else {
            netMarker.isHidden = true
        }
    }

    func hidePath() {
        dots.forEach { $0.isHidden = true }
        landingMarker.isHidden = true
        netMarker.isHidden = true
    }

    func animateRacketHit(toLocal p: SIMD3<Double>) {
        lungeTarget = p
        lungeStart = ProcessInfo.processInfo.systemUptime
    }

    func flashRacket() {
        racketFlashUntil = ProcessInfo.processInfo.systemUptime + 0.25
    }

    func animateOpponentSwing() {
        let swing = SCNAction.sequence([
            SCNAction.rotateBy(x: 0, y: -1.6, z: 0, duration: 0.12),
            SCNAction.rotateBy(x: 0, y: 1.6, z: 0, duration: 0.25)
        ])
        opponentRacket.runAction(swing)
    }

    // MARK: - 构建

    private func node(_ geometry: SCNGeometry, color: UIColor, emission: UIColor? = nil) -> SCNNode {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.lightingModel = .blinn
        if let emission { m.emission.contents = emission }
        geometry.materials = [m]
        return SCNNode(geometry: geometry)
    }

    private func box(_ w: Double, _ h: Double, _ l: Double, color: UIColor, at p: SIMD3<Double>) -> SCNNode {
        let n = node(SCNBox(width: w, height: h, length: l, chamferRadius: 0), color: color)
        n.position = SCNVector3(Float(p.x), Float(p.y), Float(p.z))
        return n
    }

    private func buildWorld() {
        scene.background.contents = UIColor(red: 0.60, green: 0.78, blue: 0.95, alpha: 1)
        scene.fogStartDistance = 40
        scene.fogEndDistance = 120
        scene.fogColor = UIColor(red: 0.60, green: 0.78, blue: 0.95, alpha: 1)

        let ground = box(80, 0.02, 100, color: UIColor(red: 0.20, green: 0.46, blue: 0.24, alpha: 1), at: SIMD3(0, -0.013, 0))
        scene.rootNode.addChildNode(ground)
        let apron = box(24, 0.02, 42, color: UIColor(red: 0.18, green: 0.34, blue: 0.60, alpha: 1), at: SIMD3(0, -0.009, 0))
        scene.rootNode.addChildNode(apron)

        // 远处的挡板和两侧围栏，给第一视角一点纵深参照
        let back = box(34, 4.5, 0.3, color: UIColor(red: 0.10, green: 0.18, blue: 0.36, alpha: 1), at: SIMD3(0, 2.25, -23))
        scene.rootNode.addChildNode(back)
        let backStripe = box(34, 0.25, 0.32, color: .white, at: SIMD3(0, 1.3, -23))
        scene.rootNode.addChildNode(backStripe)
        let behind = box(34, 4.5, 0.3, color: UIColor(red: 0.10, green: 0.18, blue: 0.36, alpha: 1), at: SIMD3(0, 2.25, 24))
        scene.rootNode.addChildNode(behind)
        for sx in [-13.5, 13.5] {
            let fence = box(0.3, 1.3, 48, color: UIColor(red: 0.14, green: 0.28, blue: 0.48, alpha: 1), at: SIMD3(sx, 0.65, 0))
            scene.rootNode.addChildNode(fence)
        }

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1000
        sun.light?.castsShadow = true
        sun.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.light?.shadowColor = UIColor(white: 0, alpha: 0.4)
        sun.light?.shadowRadius = 4
        sun.light?.automaticallyAdjustsShadowProjection = true
        sun.eulerAngles = SCNVector3(-1.05, 0.45, 0)
        scene.rootNode.addChildNode(sun)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = UIColor(white: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)
    }

    private func buildCourt() {
        let surface = box(Court.halfWidthDoubles * 2, 0.02, Court.halfLength * 2,
                          color: UIColor(red: 0.24, green: 0.46, blue: 0.78, alpha: 1), at: SIMD3(0, -0.01, 0))
        scene.rootNode.addChildNode(surface)

        let white = UIColor.white
        let lw = 0.06, lh = 0.008, y = 0.004
        func line(_ w: Double, _ l: Double, x: Double, z: Double) {
            scene.rootNode.addChildNode(box(w, lh, l, color: white, at: SIMD3(x, y, z)))
        }
        let L = Court.halfLength, Wd = Court.halfWidthDoubles, Ws = Court.halfWidthSingles
        line(Wd * 2 + lw, lw, x: 0, z: L)          // 底线
        line(Wd * 2 + lw, lw, x: 0, z: -L)
        line(lw, L * 2, x: Wd, z: 0)               // 双打边线
        line(lw, L * 2, x: -Wd, z: 0)
        line(lw, L * 2, x: Ws, z: 0)               // 单打边线
        line(lw, L * 2, x: -Ws, z: 0)
        line(Ws * 2, lw, x: 0, z: Court.serviceLineZ)   // 发球线
        line(Ws * 2, lw, x: 0, z: -Court.serviceLineZ)
        line(lw, Court.serviceLineZ * 2, x: 0, z: 0)    // 中线
        line(lw, 0.3, x: 0, z: L - 0.15)                 // 中点标记
        line(lw, 0.3, x: 0, z: -L + 0.15)
    }

    private func buildNet() {
        let mesh = node(SCNBox(width: 12.8, height: 0.95, length: 0.012, chamferRadius: 0),
                        color: UIColor(white: 0.08, alpha: 0.55))
        mesh.geometry?.firstMaterial?.isDoubleSided = true
        mesh.position = SCNVector3(0, 0.475, 0)
        scene.rootNode.addChildNode(mesh)
        let tape = box(12.8, 0.06, 0.03, color: .white, at: SIMD3(0, 0.93, 0))
        scene.rootNode.addChildNode(tape)
        for sx in [-6.4, 6.4] {
            let post = node(SCNCylinder(radius: 0.045, height: 1.07), color: UIColor(white: 0.2, alpha: 1))
            post.position = SCNVector3(Float(sx), 0.535, 0)
            scene.rootNode.addChildNode(post)
        }
        // 撞网时在网上标一个红点
        let m = node(SCNSphere(radius: 0.09), color: .systemRed, emission: .systemRed)
        netMarker.addChildNode(m)
        netMarker.isHidden = true
        scene.rootNode.addChildNode(netMarker)
    }

    private func buildBall() {
        let sphere = SCNSphere(radius: 0.075)
        sphere.segmentCount = 28
        let ball = node(sphere, color: UIColor(red: 0.85, green: 1.0, blue: 0.15, alpha: 1),
                        emission: UIColor(red: 0.30, green: 0.35, blue: 0.0, alpha: 1))
        ballNode.addChildNode(ball)
        scene.rootNode.addChildNode(ballNode)

        let shadow = node(SCNCylinder(radius: 0.09, height: 0.002), color: UIColor(white: 0, alpha: 0.45))
        shadow.castsShadow = false
        ballShadow.addChildNode(shadow)
        scene.rootNode.addChildNode(ballShadow)
    }

    private func buildOpponent() {
        let shirt = UIColor(red: 0.85, green: 0.20, blue: 0.18, alpha: 1)
        let body = node(SCNCapsule(capRadius: 0.22, height: 1.15), color: shirt)
        body.position = SCNVector3(0, 1.0, 0)
        opponentNode.addChildNode(body)
        let head = node(SCNSphere(radius: 0.14), color: UIColor(red: 0.95, green: 0.80, blue: 0.66, alpha: 1))
        head.position = SCNVector3(0, 1.72, 0)
        opponentNode.addChildNode(head)
        for sx: Float in [-0.11, 0.11] {
            let leg = node(SCNCylinder(radius: 0.08, height: 0.5), color: UIColor(white: 0.15, alpha: 1))
            leg.position = SCNVector3(sx, 0.25, 0)
            opponentNode.addChildNode(leg)
        }
        let head2 = node(SCNTorus(ringRadius: 0.14, pipeRadius: 0.013), color: UIColor(white: 0.15, alpha: 1))
        head2.eulerAngles.x = .pi / 2
        head2.position = SCNVector3(0, 0.18, 0)
        let handle = node(SCNCylinder(radius: 0.015, height: 0.3), color: UIColor(white: 0.1, alpha: 1))
        handle.position = SCNVector3(0, -0.1, 0)
        opponentRacket.addChildNode(head2)
        opponentRacket.addChildNode(handle)
        opponentRacket.position = SCNVector3(0.4, 1.15, 0.15)
        opponentNode.addChildNode(opponentRacket)

        opponentNode.position = SCNVector3(0, 0, Float(GameSession.opponentBaseZ))
        scene.rootNode.addChildNode(opponentNode)
    }

    private func buildPlayer() {
        playerRoot.position = SCNVector3(0, 0, Float(GameSession.playerBaseZ))
        scene.rootNode.addChildNode(playerRoot)

        let camera = SCNCamera()
        camera.fieldOfView = 95
        camera.projectionDirection = .horizontal
        camera.zNear = 0.05
        camera.zFar = 200
        camera.wantsHDR = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.75, 0.9)
        cameraNode.eulerAngles.x = -0.16
        playerRoot.addChildNode(cameraNode)

        // 击球区：竖着的圆环，球进入时间窗口时发亮
        let ring = SCNTorus(ringRadius: 0.32, pipeRadius: 0.02)
        hitRingMaterial.diffuse.contents = UIColor.yellow
        hitRingMaterial.emission.contents = UIColor(white: 0.25, alpha: 1)
        ring.materials = [hitRingMaterial]
        hitRing.geometry = ring
        hitRing.eulerAngles.x = .pi / 2
        hitRing.position = SCNVector3(Float(GameSession.racketX), 1.05, Float(-GameSession.hitOffset))
        hitRing.castsShadow = false
        playerRoot.addChildNode(hitRing)

        // 玩家球拍：按手机坐标系建模（y = 拍头方向，z = 屏幕法线 = 拍面）
        let handle = node(SCNCylinder(radius: 0.014, height: 0.22), color: UIColor(white: 0.12, alpha: 1))
        handle.position = SCNVector3(0, 0.0, 0)
        racketNode.addChildNode(handle)
        let frame = node(SCNTorus(ringRadius: 0.13, pipeRadius: 0.012), color: UIColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1))
        frame.eulerAngles.x = .pi / 2
        frame.position = SCNVector3(0, 0.25, 0)
        racketNode.addChildNode(frame)
        let strings = SCNPlane(width: 0.25, height: 0.25)
        racketStrings.diffuse.contents = UIColor(white: 1, alpha: 0.35)
        racketStrings.isDoubleSided = true
        strings.materials = [racketStrings]
        let stringsNode = SCNNode(geometry: strings)
        stringsNode.position = SCNVector3(0, 0.25, 0)
        stringsNode.castsShadow = false
        racketNode.addChildNode(stringsNode)
        let screenDot = node(SCNSphere(radius: 0.02), color: .systemBlue, emission: .systemBlue)
        screenDot.position = SCNVector3(0, 0.25, 0.015)
        racketNode.addChildNode(screenDot)
        racketNode.position = SCNVector3(Float(CourtScene.racketOffset.x), Float(CourtScene.racketOffset.y), Float(CourtScene.racketOffset.z))
        racketNode.eulerAngles = SCNVector3(-0.3, 0, -0.2)
        racketNode.castsShadow = false
        playerRoot.addChildNode(racketNode)
    }

    private func buildPath() {
        dotMaterial.diffuse.contents = UIColor.white
        dotMaterial.lightingModel = .constant
        for _ in 0..<80 {
            let g = SCNSphere(radius: 0.035)
            g.segmentCount = 8
            g.materials = [dotMaterial]
            let d = SCNNode(geometry: g)
            d.isHidden = true
            d.castsShadow = false
            dots.append(d)
            pathRoot.addChildNode(d)
        }
        scene.rootNode.addChildNode(pathRoot)

        let ring = SCNTorus(ringRadius: 0.42, pipeRadius: 0.035)
        landingMaterial.diffuse.contents = UIColor.systemGreen
        landingMaterial.emission.contents = UIColor.systemGreen
        landingMaterial.lightingModel = .constant
        ring.materials = [landingMaterial]
        landingMarker.geometry = ring
        landingMarker.isHidden = true
        landingMarker.castsShadow = false
        scene.rootNode.addChildNode(landingMarker)
    }
}

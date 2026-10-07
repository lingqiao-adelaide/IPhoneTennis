import UIKit

/// 挥拍手速计：三段式横条（Light / Medium / Heavy）+ 指针 + 大字读数。每次挥拍后弹出，两秒淡出。
final class PowerMeterView: UIView {
    private let valueLabel = UILabel()
    private let bar = PowerBarView()
    private var shownForSwing: TimeInterval = 0
    private var hideWork: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.55)
        layer.cornerRadius = 10
        alpha = 0
        isUserInteractionEnabled = false

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .black)
        valueLabel.textColor = .white
        valueLabel.textAlignment = .center
        valueLabel.adjustsFontSizeToFitWidth = true
        valueLabel.minimumScaleFactor = 0.6
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        addSubview(bar)
        NSLayoutConstraint.activate([
            valueLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 4),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bar.heightAnchor.constraint(equalToConstant: 30),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 每帧调用；只有出现新的挥拍才会弹出。
    func update(from swing: SwingEvent?, sticky: Bool = false) {
        guard let swing, swing.timestamp != shownForSwing else { return }
        shownForSwing = swing.timestamp
        show(handSpeed: swing.handSpeed, sticky: sticky)
    }

    func show(handSpeed: Double, sticky: Bool) {
        let cls = PowerMeterView.powerClass(handSpeed)
        valueLabel.text = String(format: "%.1f m/s · %@", handSpeed, cls.name.uppercased())
        valueLabel.textColor = cls.color
        bar.value = handSpeed
        hideWork?.cancel()
        layer.removeAllAnimations()
        alpha = 1
        transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(withDuration: 0.15) { self.transform = .identity }
        guard !sticky else { return }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.5) { self?.alpha = 0 }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    static func powerClass(_ v: Double) -> (name: String, color: UIColor) {
        if v < GameSession.lightSpeed { return ("Light", UIColor.systemGreen) }
        return ("Heavy", UIColor.systemOrange)
    }
}

/// 两段横条，刻度 0 到 maxSpeed，分界线在 lightSpeed。
final class PowerBarView: UIView {
    var value = 0.0 { didSet { setNeedsDisplay() } }
    private let maxSpeed = 9.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let barRect = CGRect(x: rect.minX, y: rect.minY + 9, width: rect.width, height: 14)
        func x(_ v: Double) -> CGFloat { rect.minX + rect.width * CGFloat(min(v, maxSpeed) / maxSpeed) }
        let zones: [(Double, Double, UIColor)] = [
            (0, GameSession.lightSpeed, .systemGreen),
            (GameSession.lightSpeed, maxSpeed, .systemOrange),
        ]
        for (a, b, c) in zones {
            ctx.setFillColor(c.withAlphaComponent(0.8).cgColor)
            ctx.fill(CGRect(x: x(a), y: barRect.minY, width: x(b) - x(a), height: barRect.height))
        }
        // 分界线 + 区间文字
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: x(GameSession.lightSpeed), y: barRect.minY - 3))
        ctx.addLine(to: CGPoint(x: x(GameSession.lightSpeed), y: barRect.maxY + 3))
        ctx.strokePath()
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: UIColor.white]
        for (a, b, _) in zones {
            let name = PowerMeterView.powerClass((a + b) / 2).name
            let size = (name as NSString).size(withAttributes: attrs)
            (name as NSString).draw(at: CGPoint(x: (x(a) + x(b)) / 2 - size.width / 2, y: barRect.maxY + 1), withAttributes: attrs)
        }
        // 指针
        let px = x(value)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.move(to: CGPoint(x: px, y: barRect.minY - 2))
        ctx.addLine(to: CGPoint(x: px - 7, y: barRect.minY - 9))
        ctx.addLine(to: CGPoint(x: px + 7, y: barRect.minY - 9))
        ctx.closePath()
        ctx.fillPath()
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: px, y: barRect.minY))
        ctx.addLine(to: CGPoint(x: px, y: barRect.maxY))
        ctx.strokePath()
    }
}

import UIKit

/// 左上角常驻的“上一次挥拍”面板：手速/档位、仰角/拍面、方向/左中右、时机、结果。
/// 每次新挥拍闪一下，给玩家自我调节的依据。
final class SwingInfoPanel: UIView {
    private let title = UILabel()
    private let rows: [(name: UILabel, value: UILabel, cls: UILabel)] = (0..<4).map { _ in (UILabel(), UILabel(), UILabel()) }
    private let bar = PowerBarView()
    private let result = UILabel()
    private var shownSwing: TimeInterval = -1
    private var shownResult = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.55)
        layer.cornerRadius = 8
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        isUserInteractionEnabled = false

        title.text = "LAST SWING"
        title.font = .systemFont(ofSize: 13, weight: .heavy)
        title.textColor = UIColor(white: 0.75, alpha: 1)

        let names = ["Speed", "Tilt", "Heading", "Timing"]
        var rowViews: [UIView] = [title]
        for (i, r) in rows.enumerated() {
            r.name.text = names[i]
            r.name.font = .systemFont(ofSize: 15, weight: .medium)
            r.name.textColor = UIColor(white: 0.8, alpha: 1)
            r.value.font = .monospacedDigitSystemFont(ofSize: 21, weight: .bold)
            r.value.textColor = .white
            r.value.text = "—"
            r.cls.font = .systemFont(ofSize: 16, weight: .heavy)
            r.cls.adjustsFontSizeToFitWidth = true
            r.cls.minimumScaleFactor = 0.7
            r.cls.textColor = .white
            r.cls.textAlignment = .right
            r.name.widthAnchor.constraint(equalToConstant: 72).isActive = true
            r.value.widthAnchor.constraint(equalToConstant: 128).isActive = true
            let h = UIStackView(arrangedSubviews: [r.name, r.value, r.cls])
            h.axis = .horizontal
            h.spacing = 6
            rowViews.append(h)
            if i == 0 {
                bar.heightAnchor.constraint(equalToConstant: 42).isActive = true
                rowViews.append(bar)
            }
        }
        result.font = .systemFont(ofSize: 14, weight: .semibold)
        result.textColor = .systemCyan
        result.numberOfLines = 2
        rowViews.append(result)

        let v = UIStackView(arrangedSubviews: rowViews)
        v.axis = .vertical
        v.spacing = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(swing: SwingEvent?, timing: String, resultText: String) {
        if let swing, swing.timestamp != shownSwing {
            shownSwing = swing.timestamp
            let power = PowerMeterView.powerClass(swing.handSpeed)
            rows[0].value.text = String(format: "%.1f m/s", swing.handSpeed)
            rows[0].cls.text = power.name.uppercased()
            rows[0].cls.textColor = power.color
            bar.value = swing.handSpeed

            let el = swing.elevationDegrees
            let faceName = SwingProfile.shared.face(el)
            let faceColor: UIColor = ["Closed": .systemRed, "Flat": .systemYellow, "Topspin": .systemGreen][faceName] ?? .systemOrange
            rows[1].value.text = String(format: "%+.0f°", el)
            rows[1].cls.text = faceName.uppercased()
            rows[1].cls.textColor = faceColor

            let h = swing.headingDegrees
            let dir = SwingProfile.shared.direction(h).uppercased()
            rows[2].value.text = String(format: "%+.0f°", h)
            rows[2].cls.text = dir
            rows[2].cls.textColor = .white
            flash()
        }
        let good = timing.hasSuffix("✓")
        let shown = timing.replacingOccurrences(of: " ✓", with: "").trimmingCharacters(in: .whitespaces)
        if rows[3].value.text != shown { rows[3].value.text = shown }
        let tc: UIColor = timing == "—" ? .white : (good ? .systemGreen : .systemOrange)
        if rows[3].value.textColor != tc { rows[3].value.textColor = tc }
        let tag = timing == "—" ? "" : (good ? "GOOD" : "OFF")
        if rows[3].cls.text != tag { rows[3].cls.text = tag; rows[3].cls.textColor = tc }
        if shownResult != resultText {
            shownResult = resultText
            result.text = resultText
        }
    }

    private func flash() {
        layer.removeAllAnimations()
        layer.borderColor = UIColor.systemCyan.cgColor
        transform = CGAffineTransform(scaleX: 1.04, y: 1.04)
        UIView.animate(withDuration: 0.6, delay: 0.1, options: [.curveEaseOut]) {
            self.transform = .identity
            self.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
        }
    }
}

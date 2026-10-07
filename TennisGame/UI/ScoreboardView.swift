import UIKit

/// 醒目的记分牌：局数、分数、等级。
final class ScoreboardView: UIView {
    private let youLabel = UILabel()
    private let cpuLabel = UILabel()
    private let gamesLabel = UILabel()
    private let pointsLabel = UILabel()
    private let levelLabel = UILabel()
    private let rallyLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0, alpha: 0.6)
        layer.cornerRadius = 10
        layer.borderWidth = 1.5
        layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
        isUserInteractionEnabled = false

        func style(_ l: UILabel, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
            l.font = .monospacedDigitSystemFont(ofSize: size, weight: weight)
            l.textColor = color
            l.textAlignment = .center
        }
        style(youLabel, size: 13, weight: .heavy, color: .systemCyan)
        style(cpuLabel, size: 13, weight: .heavy, color: .systemRed)
        style(gamesLabel, size: 30, weight: .black, color: .white)
        style(pointsLabel, size: 22, weight: .bold, color: .systemYellow)
        style(levelLabel, size: 12, weight: .heavy, color: .white)
        style(rallyLabel, size: 12, weight: .semibold, color: UIColor(white: 0.8, alpha: 1))
        youLabel.text = "YOU"
        cpuLabel.text = "CPU"
        levelLabel.backgroundColor = UIColor.systemIndigo
        levelLabel.layer.cornerRadius = 6
        levelLabel.layer.masksToBounds = true

        let top = UIStackView(arrangedSubviews: [youLabel, gamesLabel, cpuLabel])
        top.axis = .horizontal
        top.spacing = 10
        top.alignment = .center
        let bottom = UIStackView(arrangedSubviews: [levelLabel, pointsLabel, rallyLabel])
        bottom.axis = .horizontal
        bottom.spacing = 10
        bottom.alignment = .center
        let v = UIStackView(arrangedSubviews: [top, bottom])
        v.axis = .vertical
        v.spacing = 2
        v.alignment = .center
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            v.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            v.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            v.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            levelLabel.widthAnchor.constraint(equalToConstant: 64),
            levelLabel.heightAnchor.constraint(equalToConstant: 20),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func refresh(from s: GameSession) {
        let g = s.match.gamesText.replacingOccurrences(of: " : ", with: "  –  ")
        if gamesLabel.text != g { gamesLabel.text = g }
        let p = s.match.pointsText
        if pointsLabel.text != p { pointsLabel.text = p }
        let l = "LEVEL \(s.level)"
        if levelLabel.text != l { levelLabel.text = l }
        let r = "Rally \(s.rallyHits)"
        if rallyLabel.text != r { rallyLabel.text = r }
    }
}

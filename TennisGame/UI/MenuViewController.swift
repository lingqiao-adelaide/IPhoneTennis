import UIKit

/// 主菜单。进入 App 先到这里，给用户准备时间。
final class MenuViewController: UIViewController {
    var onStart: (() -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.12, blue: 0.26, alpha: 1)

        let title = UILabel()
        title.text = "Motion Tennis"
        title.font = .systemFont(ofSize: 44, weight: .black)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "iPhone as racket · TV as court · first-person 3D"
        subtitle.font = .systemFont(ofSize: 16, weight: .medium)
        subtitle.textColor = UIColor(white: 0.8, alpha: 1)
        subtitle.textAlignment = .center

        let status = UILabel()
        status.font = .systemFont(ofSize: 14, weight: .regular)
        status.textColor = .systemCyan
        status.textAlignment = .center
        status.numberOfLines = 0
        status.text = statusText()
        NotificationCenter.default.addObserver(forName: DisplayRouter.changed, object: nil, queue: .main) { [weak status, weak self] _ in
            status?.text = self?.statusText()
        }

        let start = bigButton("Start Game", color: .systemGreen)
        start.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        let cast = bigButton("Cast to TV", color: UIColor(white: 1, alpha: 0.15))
        cast.addTarget(self, action: #selector(castTapped), for: .touchUpInside)
        let help = bigButton("How to Play", color: UIColor(white: 1, alpha: 0.15))
        help.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [start, cast, help])
        buttons.axis = .horizontal
        buttons.spacing = 14
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [title, subtitle, status, buttons])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.8),
            buttons.heightAnchor.constraint(equalToConstant: 52),
        ])
    }

    private func statusText() -> String {
        DisplayRouter.shared.externalConnected
            ? "✓ TV connected: the court will show on the TV"
            : "No TV connected: the court shows on the phone (cast first for a bigger picture)"
    }

    private func bigButton(_ title: String, color: UIColor) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseBackgroundColor = color
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        let b = UIButton(configuration: config)
        b.titleLabel?.font = .systemFont(ofSize: 18, weight: .bold)
        return b
    }

    @objc private func startTapped() { onStart?() }

    @objc private func castTapped() {
        let steps = """
        1. Swipe down from the top-right corner to open Control Center
        2. Tap "Screen Mirroring" (two overlapping rectangles)
        3. Choose your TV or Apple TV
        4. Return to this app: the court shows on the TV and the phone becomes the racket

        iOS does not let apps start screen mirroring themselves; this step must be done in Control Center.
        """
        let alert = UIAlertController(title: "Cast to TV", message: steps, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default))
        present(alert, animated: true)
    }

    @objc private func helpTapped() {
        let text = """
        · After the opponent serves, swing when the ball reaches the yellow ring and the screen says "SWING!".
        · Racket face tilt sets the shot: closed face hits the net, open face lobs, too open goes long.
        · Face heading and swing direction set left / center / right.
        · Swing speed sets power (light / heavy, threshold from your calibration): light = drop shot, soft ball or lob; heavy = power drive, rally ball or deep lob.
        · Early contact pulls the ball left, late pushes it right; big errors go wide.
        · No need to move: your player runs to the ball automatically. Beat the AI by hitting to the open side or drop-shotting when it is on the baseline.
        """
        let alert = UIAlertController(title: "How to Play", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Got it", style: .default))
        present(alert, animated: true)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
}

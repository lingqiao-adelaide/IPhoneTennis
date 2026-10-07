import UIKit

/// 手机端根控制器：主菜单 → 校准 → 游戏。游戏中根据有没有电视，显示 3D 画面或球拍面板。
final class PhoneRootViewController: UIViewController {
    private enum Stage { case menu, calibration, game }
    private var stage: Stage = .menu
    private var current: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        NotificationCenter.default.addObserver(self, selector: #selector(displayChanged),
                                               name: DisplayRouter.changed, object: nil)
        showMenu()
        #if DEBUG
        // 调试：环境变量 START_STAGE=calibration|game 直接跳到某个页面
        switch ProcessInfo.processInfo.environment["START_STAGE"] {
        case "calibration": showCalibration()
        case "session":
            showCalibration()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                let vc = CalibrationSessionViewController()
                vc.modalPresentationStyle = .fullScreen
                self?.current?.present(vc, animated: false)
            }
        case "game": startGame()
        default: break
        }
        #endif
    }

    private func showMenu() {
        stage = .menu
        GameSession.shared.endMatch()
        let menu = MenuViewController()
        menu.onStart = { [weak self] in self?.showCalibration() }
        show(menu)
    }

    private func showCalibration() {
        stage = .calibration
        let cal = CalibrationViewController()
        cal.onReady = { [weak self] in self?.startGame() }
        cal.onBack = { [weak self] in self?.showMenu() }
        show(cal)
    }

    private func startGame() {
        stage = .game
        GameSession.shared.beginMatch()
        showGameScreen()
    }

    private func showGameScreen() {
        if DisplayRouter.shared.externalConnected {
            if current is ControllerViewController { return }
            let c = ControllerViewController()
            c.onExit = { [weak self] in self?.showMenu() }
            show(c)
        } else {
            if let g = current as? GameViewController, g.mode == .phone { return }
            let g = GameViewController(mode: .phone)
            g.onExit = { [weak self] in self?.showMenu() }
            show(g)
        }
    }

    @objc private func displayChanged() {
        if stage == .game { showGameScreen() }
    }

    private func show(_ next: UIViewController) {
        current?.willMove(toParent: nil)
        current?.view.removeFromSuperview()
        current?.removeFromParent()
        addChild(next)
        next.view.frame = view.bounds
        next.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(next.view)
        next.didMove(toParent: self)
        current = next
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}

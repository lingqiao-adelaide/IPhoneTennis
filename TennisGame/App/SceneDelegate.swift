import UIKit

/// 手机屏幕。没有电视时显示 3D 游戏；连上电视后切换成“球拍控制面板”。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = PhoneRootViewController()
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // 每次回到前台都重新声明一次，保险起见（系统偶尔会在后台/前台切换时重置）。
        UIApplication.shared.isIdleTimerDisabled = true
        GameSession.shared.setPaused(false)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        GameSession.shared.setPaused(true)
    }
}

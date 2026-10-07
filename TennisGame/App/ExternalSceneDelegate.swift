import UIKit

/// 外接屏幕（AirPlay 镜像 / HDMI 转接）。电视上只渲染 3D 游戏画面，不接受触摸。
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = GameViewController(mode: .television)
        self.window = window
        window.isHidden = false
        DisplayRouter.shared.externalConnected = true
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        window = nil
        DisplayRouter.shared.externalConnected = false
    }
}

/// 记录当前是否有电视接入，手机端据此切换界面。
final class DisplayRouter {
    static let shared = DisplayRouter()
    static let changed = Notification.Name("DisplayRouter.changed")

    var externalConnected = false {
        didSet { NotificationCenter.default.post(name: DisplayRouter.changed, object: self) }
    }
}

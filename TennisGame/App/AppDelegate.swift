import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 整个游戏靠挥动手机，不会触摸屏幕：必须关闭自动锁屏，否则打到一半就黑屏。
        application.isIdleTimerDisabled = true
        GameSession.shared.start()
        return true
    }

    // 主屏幕（手机）和外接屏幕（AirPlay 镜像到电视时系统会给出一个 external display scene）
    // 走不同的 SceneDelegate：电视上放 3D 游戏画面，手机上放球拍状态面板。
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowExternalDisplayNonInteractive {
            config.delegateClass = ExternalSceneDelegate.self
        } else {
            config.delegateClass = SceneDelegate.self
        }
        return config
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

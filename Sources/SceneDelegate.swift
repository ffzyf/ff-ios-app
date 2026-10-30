//
//  SceneDelegate.swift
//  SkyApp
//
//  窗口场景装配：创建 UIWindow 并挂载 RootTabBarController。
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController()
        window.makeKeyAndVisible()
        self.window = window
    }
}

//
//  AppDelegate.swift
//  SkyApp
//
//  应用入口。仅负责生命周期装配：把窗口场景交给 SceneDelegate。
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Info.plist 中的 UIApplicationSceneManifest 已声明了同名配置，
        // 这里显式设置 delegateClass，确保 SceneDelegate 一定被实例化。
        let configuration = UISceneConfiguration(name: "Default Configuration",
                                                sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

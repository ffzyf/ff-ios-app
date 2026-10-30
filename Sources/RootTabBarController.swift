//
//  RootTabBarController.swift
//  SkyApp
//
//  根容器：按 AppConfig.tabs 生成四个 WebViewController，每个包一层导航控制器。
//

import UIKit

final class RootTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // 不设置 overrideUserInterfaceStyle，跟随系统深浅色。
        applyTabBarAppearance()
        buildTabControllers()
    }

    /// 配置 TabBar 外观。iOS 15 起 standardAppearance 与 scrollEdgeAppearance
    /// 必须同时设置，否则滚动到边缘时背景会变透明。
    private func applyTabBarAppearance() {
        tabBar.tintColor = AppConfig.primaryColor

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    /// 按配置顺序创建四个 Tab。
    private func buildTabControllers() {
        var controllers: [UIViewController] = []

        for tab in AppConfig.tabs {
            let webViewController = WebViewController(tab: tab)
            let navigationController = UINavigationController(rootViewController: webViewController)

            // 隐藏系统导航栏（页面标题由网页自身呈现）。
            // 不启用系统侧滑返回手势：本 App 每个 Tab 都是单视图控制器栈，该手势收益为 0，
            // 却与 WKWebView 自带的网页返回手势冲突，容易导致整页卡死/黑屏。
            navigationController.isNavigationBarHidden = true

            navigationController.tabBarItem = AppConfig.makeTabBarItem(for: tab)
            controllers.append(navigationController)
        }

        viewControllers = controllers
    }
}

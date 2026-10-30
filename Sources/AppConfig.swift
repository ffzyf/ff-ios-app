//
//  AppConfig.swift
//  SkyApp
//
//  应用全局配置：四个站点的唯一配置源。
//  修改站点、标题、图标只需改动本文件。
//

import UIKit

/// 单个底部 Tab 的静态配置。
struct AppTab {
    /// Tab 标题，同时作为页面导航标题。
    let title: String
    /// 站点完整地址，必须包含协议头（https://）。
    let urlString: String
    /// SF Symbol 名称，系统找不到时图标为空，不会崩溃。
    let systemImage: String
}

/// 应用级常量集合。
enum AppConfig {

    /// 应用展示名，与 Info.plist 中的 CFBundleDisplayName 保持一致。
    static let appName: String = "FF大王"

    /// 追加到 User-Agent 末尾的标识，便于站点侧区分 App 来源。
    static let customUserAgentSuffix: String = " FFWang/1.0"

    /// 主题色（青柠绿 #6BDB5C）。
    static let primaryColor: UIColor = UIColor(red: 0.420, green: 0.859, blue: 0.361, alpha: 1.0)

    /// 四个站点的顺序定义：博客、简报、收益、问卷。
    static let tabs: [AppTab] = [
        AppTab(title: "博客",
               urlString: "https://skyzyf335.top",
               systemImage: "doc.text"),
        AppTab(title: "简报",
               urlString: "https://app.skyzyf335.top",
               systemImage: "bell.badge"),
        AppTab(title: "收益",
               urlString: "https://gzz.skyzyf335.top",
               systemImage: "chart.line.uptrend.xyaxis"),
        AppTab(title: "问卷",
               urlString: "https://wj.skyzyf335.top",
               systemImage: "list.bullet.clipboard")
    ]

    /// 根据 Tab 配置生成 UITabBarItem。
    /// - Parameter tab: 目标 Tab 配置。
    /// - Returns: 已配置标题与图标的 UITabBarItem。
    static func makeTabBarItem(for tab: AppTab) -> UITabBarItem {
        // UIImage(systemName:) 返回可选值；UITabBarItem 的 image 参数本身可空，
        // 因此这里直接传递，无需强制解包。
        let icon: UIImage? = UIImage(systemName: tab.systemImage)
        let item = UITabBarItem(title: tab.title, image: icon, selectedImage: icon)
        return item
    }
}

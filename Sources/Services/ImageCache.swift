import SwiftUI
import Foundation

/// URLCache 统一配置。
///
/// 图片策略（设计文档 §8.4）：
///   · 协议层：全局 `URLCache`（内存 20MB / 磁盘 200MB），接口 JSON 与图片字节共用
///   · 解码层：直接用系统 `AsyncImage` —— 它自带 `URLCache` 命中，**不需要**我们自建 ImageLoader
///
/// 3.11.0 清理：这里原本还有一个 `RemoteImage<Placeholder>` 包装视图（占位渐变块 + 失败态图标），
/// 全工程零引用 —— 真正的图片位都直接写 `AsyncImage`，包装层只是把 `AsyncImage` 的
/// 三个 phase 又转述了一遍。删掉它之后本文件只剩「一次 `URLCache` 配置」这一件事。
enum ImageCache {
    /// 在 App 启动、第一个请求之前调用（见 `FFWangApp.init`）。
    static func configure() {
        URLCache.shared = URLCache(
            memoryCapacity: 20 * 1024 * 1024,
            diskCapacity: 200 * 1024 * 1024
        )
    }
}

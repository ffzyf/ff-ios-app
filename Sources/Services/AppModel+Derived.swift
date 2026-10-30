import Foundation

/// `AppModel` 的**只读派生数据**（视图只读这些，不用自己 switch `LoadState`）。
///
/// 单独成文件的理由：这一组属性是「页面需要什么」的投影，全部只读、互不依赖顺序，
/// 与「怎么写状态」（加载 / 失败归并）是两件事。拆开也让 `AppModel.swift` 守住行数红线。
/// 放在这里不改任何可见性：`@Published private(set)` 的 getter 本来就是 internal，setter 仍只属于本体文件。
extension AppModel {

    var pinnedArticles: [ArticleSummary] {
        return feedState.value?.articles.pinned ?? []
    }

    /// 已加载的文章（`loadFeed(page:append:)` 的追加结果就在这里，翻页不会顶掉前面的）
    var articles: [ArticleSummary] {
        return feedState.value?.articles.items ?? []
    }

    var hasMoreArticles: Bool {
        return feedState.value?.articles.hasMore ?? false
    }

    /// 当前已加载到第几页（1 = 只有第一页；`append` 合并后会跟着前进）
    var feedPage: Int {
        return feedState.value?.articles.page ?? 1
    }

    var notice: FeedNotice? {
        return feedState.value?.notice
    }

    var stats: FeedStats? {
        return feedState.value?.stats
    }

    /// 版本段：简报接口一定带；feed 里是历史遗留的可空字段（取不到就 nil）
    var skyStatus: SkyStatus? {
        if let sky = briefState.value?.sky {
            return sky
        }
        return feedState.value?.sky
    }

    /// 今日简报快照
    var todayBrief: BriefSnapshot? {
        return briefState.value?.brief
    }

    /// 首屏是否有任何内容可渲染（决定显示骨架还是错误态）
    var hasAnyContent: Bool {
        return feedState.hasContent || briefState.hasContent
    }
}

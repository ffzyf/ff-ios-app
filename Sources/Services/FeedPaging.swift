import Foundation

/// 「追加一页」的合并逻辑（`AppModel.loadFeed(page:append:)` 的唯一实现点）。
///
/// 为什么放在 `FeedResponse` 的扩展里而不是 `AppModel` 里：这是一次纯数据变换
/// （旧的一摞 + 新的一页 → 合并结果），不需要任何状态，单独放才能被单测直接调用。
///
/// 为什么 merge 结果能重建：`FeedResponse` 的字段全是 `let`，重建靠的是
/// `Models/FeedResponse.swift` 类型体内的全字段 init（extension 里的 init 不允许给 `let` 赋值）。
extension FeedResponse {

    /// 追加语义：`items` = 已有 items + 新页里没出现过的（按 id 去重）；
    /// `pinned` 保留第一页那份（置顶区独立渲染，翻页不该把置顶搬两遍）；
    /// `page` / `hasMore` / `total` 取新一页的 —— 分页判停只认 `hasMore`。
    func merging(existing: FeedResponse) -> FeedResponse {
        let knownIDs = Set(existing.articles.items.map { $0.id })
        let fresh = articles.items.filter { knownIDs.contains($0.id) == false }
        let merged = FeedArticles(
            pinned: existing.articles.pinned,
            items: existing.articles.items + fresh,
            page: articles.page,
            size: articles.size,
            total: articles.total,
            hasMore: articles.hasMore
        )
        return FeedResponse(
            ok: ok,
            apiVersion: apiVersion,
            serverTime: serverTime,
            generatedAt: generatedAt,
            articles: merged,
            notice: existing.notice,
            stats: existing.stats,
            sky: existing.sky,
            brief: existing.brief
        )
    }
}

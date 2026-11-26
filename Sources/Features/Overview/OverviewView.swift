import SwiftUI
import Foundation

/// 概览首页（Tab 1）。
///
/// 版式（设计报告 §4.1，3.27.0 起上半屏改成一对**等高**卡）：组间 32 / 组内 12：
/// ```
/// 日期头
/// ─ 32 ─
/// 公告横幅（远程配置下发才有，3.9.0 热更通道）
/// ─ 32 ─
/// 红石 medium 168                  ┐ 组内 12
/// 简报 medium 168                  │
/// AI 穿搭卡（高自适应，3.28.0）      ┘
/// ─ 32 ─
/// 「今日一览」+ 两张 96 tile
/// ─ 32 ─
/// 「继续读」+ rail 140×188（无文章时整块不渲染）
/// ─ 32 ─
/// 「快捷」+ 3 枚胶囊
/// ```
///
/// 改版动机（报告 §1）：原来一页并存两套组距（12 与 24），三张大卡同宽同高同阴影，
/// 没有 22pt 分区标题、没有横向滚动、没有一张图 —— 空不是块少，是每块"内容占比"低且块间无差。
///
/// 职责边界不变：数据只从 `AppModel` / `RockStore` 读（页面绝不自己发请求），
/// Tab 状态由 `RootView` 通过 `selectedTab` 注入。
///
/// 3.28.0 唯一的例外是首屏那张 AI 穿搭卡：它自带数据源（`AIOutfitStore`，6 小时缓存），
/// 由**卡片自己**在"天气变了 / 回到前台"时刷新。那份数据与本站的 feed 完全无关，
/// 塞进 `AppModel` 只会让两个不相干的网络域互相牵连（feed 失败要连带清空 AI 卡，
/// 而那没有道理）。页面本身仍然一行请求都不发。
struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    /// 尺寸模型（设计文档 §3.2）：概览是**单列**页 —— 一屏一个锚点，红石与简报并排会让
    /// 两个"此刻"互相打架。
    ///
    /// 注：3.27.0 起两张卡已经等高（都是 168），所以当初"240 与 168 不等高、并排必然一块矮一截"
    /// 这条理由**不再成立** —— 单列的依据只剩"一屏一个锚点"。真要改成并排，是下一次版式决定，
    /// 不在这次（用户只要求等高）。
    @Environment(\.layoutMetrics) private var metrics
    /// 红石数据不再由本页直读：hero 卡自己从环境取 `RockStore`。
    /// 请求仍由 `RootView` 的 task 统一发起（页面绝不自己开请求，§7.3）。
    @Binding private var selectedTab: AppTab
    /// 滚动偏移保活（B3）：由 RootView 持有字典并作为 Binding 注入，切 Tab 回来大致回到原位。
    private let scrollPosition: Binding<ScrollPosition>

    @State private var showsSettings: Bool = false
    /// 沉浸式天光页（3.11.0）。第二张卡（`TodayBriefTrackCard`）的「今日」是它**唯一**的 App 内入口。
    ///
    /// 为什么由本页持有而不是甩给 `RootView`：弹出状态跟着"谁发起"走，
    /// `RootView` 只需要管深链那一条（DESIGN-RULES §4：入口只有两处）。
    @State private var showsSkyRoom: Bool = false

    /// 公告横幅的数据源（3.9.0）。单例直读 + ObservedObject：配置到达时横幅原地出现，
    /// 不需要整页刷新。页面不发请求 —— 拉取由 `FFWangApp` 的 task 统一驱动（§7.3 同一条纪律）。
    @ObservedObject private var config = RemoteConfigStore.shared

    /// 走**普通**弹窗形态的公告（5.3.0）。非 nil 时 `.sheet(item:)` 起层。
    ///
    /// 为什么用可选的 item 而不是 `isPresented` + 另存一份公告：闭包里拿到的是
    /// **非可选**的公告，层内不用再判空，也就没有"空弹层"这种中间态（同 `UpdateSheet`）。
    @State private var sheetAnnouncement: AnnouncementSheetItem?

    /// 走**紧急**整屏形态的公告（5.4.1）。非 nil 时 `.fullScreenCover(item:)` 起层。
    ///
    /// 为什么要和 `sheetAnnouncement` 分成两个状态、两个 modifier：同一个 binding 同时挂在
    /// `.sheet` 和 `.fullScreenCover` 上时，SwiftUI 只有一个模态能在场，谁先响应谁赢 ——
    /// 那是一个"点了发布、有时全屏有时半屏"的竞态。两个状态 + task 里按 `isEmergency`
    /// **二选一**赋值，模态归属在代码里就是确定的。
    @State private var emergencyAnnouncement: AnnouncementSheetItem?

    /// 本进程内**已经起层展示过**的 revision（不是"尝试过"）。
    ///
    /// 只用来防"同一次启动里重复起层"：`task(id:)` 在 tab 切回、`.sheet` 关掉后都可能重跑，
    /// 没有这道闸，用户不关、切个 tab 回来就再弹一次。
    ///
    /// 类型是 `Int?` 而不是 `Bool`：布尔只能表达"这个进程弹过了"，
    /// 于是"先弹了 revision 7 的普通公告、一小时后拉到 revision 8 的紧急公告"会被永久挡在门外
    /// （5.4.0 的真机 bug：服务中断通知被一个进程级标志吃掉，杀进程才恢复）。
    /// 记住**具体弹过哪个 revision**，新 revision 就是一次新的机会。
    ///
    /// 与 `AnnouncementMemory` 的分工：后者**跨启动落盘**，回答"用户是不是点过按钮了"；
    /// 这里只活在本次进程，回答"这个 revision 是不是已经在本进程起过层了"。两者不可合并 ——
    /// 落盘那份要能跨启动生效又不能因为一次取消的 sleep 被写脏。
    @State private var lastOfferedRevision: Int?

    init(selectedTab: Binding<AppTab>, scrollPosition: Binding<ScrollPosition>) {
        self._selectedTab = selectedTab
        self.scrollPosition = scrollPosition
    }

    var body: some View {
        ScrollView {
            // 组间 32：`sectionGapLoose`（= 2.67 × 组内 12），层级靠间距差读出来
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                OverviewHeader(lunar: lunarText) {
                    showsSettings = true
                }
                announcementSlot
                topGroup
                loadedBlocks
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.page)
            .padding(.top, 8)
            .padding(.bottom, Spacing.pageBottomInset)
            // 列宽：bento 行只在 rail 档出现（canvas ≥ 1040），此时读画布；否则 720（= 今天）。
            //
            // **不能用 `gridPageWidth`**：它在 canvas 760…1019（834 / 1024 竖屏）也会返回画布，
            // 而概览在那些尺寸上仍然是**单列 720** 的版式（设计文档 §3.2 注：rail 页在
            // rail 不成立时一律退回 single 720）。用 gridPageWidth 会让竖屏的首页正文
            // 从 680 变成 984 宽 —— 一行 60 多个汉字，正是 R9 禁止的事。
            //
            // `railPageWidth` 已经含页边距（宽档 = 1080 + 40），页面里不要再减 40。
            // 窄屏 393 < 720，`maxWidth` 不生效 → 与 3.7.0 逐像素一致。
            .pageColumn(metrics.railPageWidth)
        }
        .scrollPosition(scrollPosition)
        .pageScrollLight()
        .scrollIndicators(.hidden)
        // PRD §5.2「离线（有缓存）」：有内容但这次刷新失败 → 顶部细条。
        // 用 `safeAreaInset` 而不是 overlay：细条占据自己的高度，不压住标题、不遮内容。
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsOfflineBanner {
                OfflineBanner()
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, 6)
                    // 细条与主体同列宽。**照抄 body 里那条表达式**而不是写死 720：
                    // 写死会让宽档（画布 1080）的胶囊比内容列窄 360、左右各缩进 180，
                    // 变成一条"没对齐"的横杠。窄屏 720 > 393，`maxWidth` 不生效 → 零影响。
                    .pageColumn(metrics.railPageWidth)
            }
        }
        .refreshable {
            await model.refresh()
        }
        // ⌘R（设计文档 §7.1）：走的就是下拉刷新同一个方法，不另开一条请求路径 ——
        // 两条路径会让"下拉能刷出来、⌘R 刷不出来"这种差异成为可能。
        .refreshShortcut {
            Task { await model.refresh() }
        }
        // 全站共享的轻提示（B2 后来源是 ToastStore，这里不传文案即读全局）
        .overlay(alignment: .bottom) {
            PageToast()
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        // 公告弹层（5.3.0，5.4.0 起分两级，5.4.1 起两种模态各挂各的）。
        //
        // 5.4.0 曾把分叉放在 `.sheet` 的**闭包里**（同一个 item，换内容视图），理由是
        // "两个 modifier 争同一个 item"。那个理由对普通弹窗成立，对紧急公告不成立：
        // `.presentationDetents([.large])` 在 iPhone 上顶部留缝、在 iPad 上是居中卡片 ——
        // 紧急公告要的是"压住首页"，半屏卡片做不到。它必须换模态，而不只是换内容。
        //
        // 所以现在是两个独立的 item、两个独立模态：普通 → `.sheet`（半屏起步、可下滑关），
        // 紧急 → `.fullScreenCover`（整屏、无下滑手势）。task 里按 `isEmergency` 二选一赋值，
        // 两条路径互斥，不会出现同一个 binding 被两个模态抢。
        .sheet(item: $sheetAnnouncement) { item in
            AnnouncementSheet(announcement: item.announcement, revision: item.revision)
        }
        .fullScreenCover(item: $emergencyAnnouncement) { item in
            AnnouncementEmergencySheet(announcement: item.announcement, revision: item.revision)
        }
        // 什么时候弹：配置到了、这条公告的呈现形态是弹层、本 revision 还没读过。
        //
        // 延迟 0.45s 才起层：开屏瞬间盖一层弹窗，用户会以为"这 App 打开就是广告"，
        // 连首页长什么样都没看见就先被打断。等一下让页面先落位，
        // 弹窗就更像"首页上方浮起来的东西"，而不是"这个 App 的门"。
        //
        // **紧急公告也走这个延迟**（`presentation` 对紧急恒为 `.sheet`，所以这里不用特判）：
        // 提前 450ms 弹出来并不会让"紧急"更紧急，只会让开屏更像一次意外；
        // 而"紧急"的全部表达力在那一层弹窗内部（整屏 / 只能点按钮 / 不跟主题），不在弹得多快。
        //
        // 三道闸门，各管一件事（5.4.1 修过一次把紧急公告饿死的 bug，别再把它们合成一个布尔）：
        // ① `presentation == .sheet`：横幅形态不进弹层（同一条内容不能两条通道都出）。
        // ② `AnnouncementMemory.hasRead`：跨启动落盘，"用户点过按钮了就不再弹"，
        //    普通 / 紧急一视同仁 —— 紧急公告也不该在用户已经确认之后再拦一次。
        // ③ `lastOfferedRevision`：**只防本进程内重复起层**，且**只对普通公告生效**。
        //    紧急公告不看它：它是"必须看到"，宁可因为 revision 变化在本进程里再起一次层，
        //    也不能让一个进程级标志吞掉服务中断通知。
        .task(id: config.latest?.revision) {
            guard let announcement = config.latest?.values?.announcement,
                  announcement.presentation == .sheet else { return }
            let revision = config.latest?.revision ?? 0
            guard AnnouncementMemory.hasRead(revision) == false else { return }
            if announcement.isEmergency == false {
                guard lastOfferedRevision != revision else { return }
            }

            try? await Task.sleep(for: .milliseconds(450))
            // 记"展示过"必须在 sleep **之后**：这 450ms 里 task 随时可能被取消
            // （切走这一页、revision 又变了）。在 sleep 之前置位的话，一次被取消的等待
            // 就会被记成"已经弹过了"，本次启动再也没有机会弹它 —— 5.4.0 的第二个 bug。
            guard Task.isCancelled == false else { return }

            let item = AnnouncementSheetItem(announcement: announcement, revision: revision)
            lastOfferedRevision = revision
            if announcement.isEmergency {
                emergencyAnnouncement = item
            } else {
                sheetAnnouncement = item
            }
        }
        // 天光页（3.11.0）：全屏呈现，环境值（layoutMetrics / reduceMotion）由模态继承
        .fullScreenCover(isPresented: $showsSkyRoom) {
            // 同上：把简报快照带进去，朗读才有"宜/忌"可念
            SkyRoomView(brief: model.todayBrief)
        }
    }

    // MARK: - 公告横幅

    /// 远程配置下发的公告（3.9.0）。announcement 缺失 / 已被本 revision 关闭时整条不渲染
    /// —— 首页版式回到与 3.8.x 逐行一致，横幅是"叠加项"而不是"占位项"。
    ///
    /// 5.3.0 起多一个条件：`style == .sheet` 的公告**不进横幅位**。
    /// 同一条内容既挂横幅又弹窗，等于在用户关闭横幅之后又被拦一次 —— 那不叫强调，叫骚扰。
    ///
    /// 5.4.0 起第二个条件：**紧急公告永不进横幅位**（`isEmergency == false`）。
    /// 理由与上面同源、但更强：紧急公告的语义是"必须看到"，而横幅一按 × 就记账已读
    /// （`AnnouncementBanner.close`）—— 同一条公告既出横幅又出弹窗，用户点掉横幅之后
    /// 弹窗还在，两条通道的说法互相抵消，用户只会觉得这个 App 在耍赖。
    /// 注意这里判的是 `isEmergency` 而不是 `presentation`：`presentation` 对紧急公告
    /// 恒为 `.sheet`，两个条件在今天的实现下等价；但 `isEmergency` 读的是**意图**，
    /// 万一将来给紧急公告加第三种呈现，这条闸门不需要跟着改。
    @ViewBuilder
    private var announcementSlot: some View {
        if let announcement = config.latest?.values?.announcement,
           announcement.isEmergency == false,
           announcement.presentation == .banner,
           announcement.title.isEmpty == false || announcement.body.isEmpty == false {
            AnnouncementBanner(
                announcement: announcement,
                revision: config.latest?.revision ?? 0
            )
        }
    }

    // MARK: - 首屏两张主卡（同一组）

    /// hero + medium：它们回答同一件事（"此刻"），所以组内 12、不与下一组等距。
    ///
    /// 两张卡**恒定渲染**、与 feed 的加载状态解耦 —— feed 慢或挂了，首页上半屏依然是完整内容，
    /// 不会出现"整页灰骨架"（红石卡的数据源与 feed 完全不同域，没有理由被连坐）。
    ///
    /// **宽档（rail / bento）改横排**：712 的大卡 + 344 的右栏（设计文档 §4.1）。
    /// 分叉只有这一处，两个分支里的卡片、组件、动作全部是同一批定义 —— 宽档改的是"谁在谁旁边"，
    /// 不是"再写一套首页"。窄档分支是纵向的两张 **168** 高等高卡（3.27.0 从这里开始与 3.7.0 不同，
    /// 见下）。
    ///
    /// **3.27.0：窄档红石卡 240 → 168（`tier: .hero` → `.medium`）**。
    /// 用户过图之后要的是「红石卡与下面那张天气卡等高」：两张卡说的是同一件事（此刻），
    /// 一高一矮却不并排，读起来就是"上半截更重要的错觉"，而红石卡里真正重要的只有
    /// 大字 / 倒计时 / 进度轨 —— 多出来的 72pt 全给了留白。
    /// **宽档那处一个字符都不动（仍是 `.hero` / 344）**：iPad 是横排，左 712 宽卡 + 右 344 右栏，
    /// 344 是栅格推出来的（40 标题 + 120 tile + 12 + 172 简报），改了右栏就撑不住。
    /// `CardTier.hero.height = 240` 也保持原值：简报页等别处还在用这一档。
    ///
    /// 判据用 `usesRail` 而不是 `gridColumns == 3`：概览的 bento 行只在"画布 ≥ 1040"时成立，
    /// 1020…1039 那条窄带里它按 §3.2 的约定退回单列（与红石 / 简报 / 更多一致）。
    @ViewBuilder
    private var topPair: some View {
        if metrics.usesRail {
            HStack(alignment: .top, spacing: Layout.gridGutter) {
                RedstoneCountdownCard(tier: .hero, onOpenRock: openRock)
                    // 712 由"344×2 + 24"推出来，但这里用 `maxWidth: .infinity` 让它自己吃掉
                    // 剩余宽度：1020…1039 那条窄带里列宽不是 344，写死 712 会横向溢出被裁。
                    .frame(maxWidth: .infinity)
                overviewSideColumn
                    // 高度给死 344（= `cardHeight(.hero)`）：
                    // ① 右栏里的简报卡用 `maxHeight: .infinity` 撑满剩余空间（168 → 172），
                    // ② 左右两块底边因此严格齐平，不需要任何 `Spacer` / 测量。
                    // 不给高度的话，`ScrollView` 里 `HStack` 拿到的是"高度未定"的 proposal，
                    // 右栏只会按内容自然高排，简报卡撑不到 172、底边差 4–8pt。
                    .frame(
                        width: metrics.gridColumnWidth,
                        height: metrics.cardHeight(.hero),
                        alignment: .top
                    )
            }
        } else {
            // 窄档：两张 **168** 等高的卡（3.27.0 用户过图确认的版式）。
            //
            // 判据与卡高是同一件事的两面：这里传 `.medium`，卡内部的 `minHeight` 走
            // `metrics.cardHeight(.medium)` = 168，与下面那张简报卡（也是 `.medium`）严格等高 ——
            // 不需要在 VStack 上加任何 `.frame(height:)` 去"对齐"，等高是**同一档位**的自然结果。
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                RedstoneCountdownCard(tier: .medium, onOpenRock: openRock)

                TodayBriefTrackCard(snapshot: model.todayBrief) {
                    openSkyRoom()
                }
            }
        }
    }

    // MARK: - 首屏那一组（"此刻"）

    /// 首屏一组：红石卡 + 天气卡 + **AI 穿搭卡**（3.28.0）。
    ///
    /// ## 穿搭卡为什么放在这里
    ///
    /// 三个候选位置，只有这里成立：
    /// · **放进「今日一览」那一组**：那组是"读数"（红石几场 / 距日落），穿搭卡是一段话，
    ///   放进去会让 22pt 分区标题下面既有一行字又有两张 tile，读者分不清谁是标题的下属；
    /// · **放在页面最下面**：它是"今天出门穿什么"，是最容易被一天开头就用到的信息，
    ///   埋在「继续读」后面等于没有；
    /// · **紧跟天气卡（选它）**：它和天气卡说的是同一件事的两个层次 ——
    ///   天气卡报"今天 12°、多云"，穿搭卡说"所以穿薄外套"。两张卡挨着，
    ///   用户不需要在大脑里做一次跳转。
    ///
    /// 所以它与红石卡、天气卡**同一组**（组内 12 `cardGap`），与下一组隔 32
    /// （`sectionGapLoose`）—— 间距差本身就是"这是一组的"这句话。
    ///
    /// 注意：它在 `loadedBlocks` **之外**。`loadedBlocks` 会因为 feed 请求失败整块换成
    /// 错误态，而穿搭卡的数据源（`AIOutfitStore`，POST /api/ai/outfit）与 feed 完全无关，
    /// 没有理由被连坐 —— 首页不该因为博客挂了就少一块。
    private var topGroup: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            topPair
                // 5.7.0 redesign：首屏卡片依次入场（每张 60ms 错开）。
                // reduceMotion 时位移/缩放/stagger 全归零，卡片同时淡入。
                .staggerIn(index: 0)
            AIOutfitCard()
                .staggerIn(index: 1)
        }
    }

    /// grid3 档 Row A 的右栏：简报摘要（168 → 172，被拉伸）+「今日一览」两张 tile。
    ///
    /// 172 + 12 + 40（分区标题）+ 120（tile）= 344 = hero 高 —— 这是"两个数字来自同一张栅格"
    /// 的直接结果（设计文档 §4.1），不是凑出来的。
    private var overviewSideColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.cardGap) {
            TodayBriefTrackCard(snapshot: model.todayBrief) {
                openSkyRoom()
            }
            .frame(maxHeight: .infinity)

            versionsSection
        }
    }

    // MARK: - 状态分发

    /// 有内容就渲染内容；第一次就失败才整页错误态（PRD §7：错误态不清空已有内容）
    @ViewBuilder
    private var loadedBlocks: some View {
        if model.hasAnyContent {
            VStack(alignment: .leading, spacing: Spacing.sectionGapLoose) {
                // 「今日一览」在 grid3 档被搬进 Row A 的右栏（它现在与 hero 同一行），
                // 这里就不再重复渲染一次 —— 同一屏出现两组完全相同的版本 tile 是最典型的"半成品"。
                if showsVersionsInline {
                    versionsSection
                }
                if continueReadingArticles.isEmpty == false {
                    continueReadingSection
                }
                quickSection
            }
        } else if let error = firstError {
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: {
                    Task { await model.refresh() }
                }
            )
        } else {
            // 轻量骨架：只托住还没到的分区，不再整页铺 6 块灰条。
            // 高度走 `cardHeight(.tile)`：宽档是 120，与最终渲染出来的 tile 等高，收起时不跳。
            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                SkeletonBlock(height: metrics.cardHeight(.tile), cornerRadius: Radius.card)
                SkeletonBlock(height: metrics.cardHeight(.tile), cornerRadius: Radius.card)
            }
        }
    }

    /// 「今日一览」留在正文流里吗？bento 档它在 Row A 的右栏里。
    private var showsVersionsInline: Bool {
        return !metrics.usesRail
    }

    /// 「今日一览」：两张 96 tile（原 `SkyStatusCard` 整卡留给简报页）
    private var versionsSection: some View {
        // spacing 0：`SectionHeader` 自带 12pt 下距，这里再加一次会变成 24（等于又造一套组距）
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "今日一览", actionTitle: "全部", action: openBrief)
            VersionTileRow(status: model.skyStatus, onTap: openBrief)
        }
    }

    /// 「继续读」：**窄档横滑 rail / 宽档 3 列网格**，同一份数据、同一个入口。
    ///
    /// 为什么宽档不继续用 rail：140×188 的竖卡在 1080 的画布上一行只放 6 张、还露出半张，
    /// 而它横向只看得到 8 篇里的 4 篇 —— 屏幕宽了 3 倍、信息量却没变（设计文档 §1.1 的"唯一没退化的一块"）。
    /// 换成 3 列 344×116 的列表卡，一行 3 篇、两行 6 篇，是高宽比 2.97:1（≈ iPhone 的 3.04:1）。
    ///
    /// **没有文章就整块不渲染** —— 宁可少一组，不画空卡。
    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "继续读", actionTitle: "更多", action: openArticles)
            if metrics.usesRail {
                LazyVGrid(
                    columns: continueReadingColumns,
                    alignment: .leading,
                    // 行距用 12（组内节奏），栏距由 `GridItem.spacing` 给 24（栅格）。
                    // 两个方向本来就不同：栅格是"画布怎么切"，行距是"同组内两张卡隔多远"。
                    spacing: Spacing.cardGap
                ) {
                    ForEach(continueReadingArticles) { article in
                        ArticleRowCard(article: article) {
                            openArticles()
                        }
                    }
                }
            } else {
                // 出血只对"列宽 = 屏宽"成立。宽屏列宽 720 < 1194，继续出血会让卡片滑到列外
                // 压在空白上（§4.3），所以由 `allowsRailBleed` 决定。窄屏它恒为 true → 与今天一致。
                Rail(bleeds: metrics.allowsRailBleed) {
                    ForEach(continueReadingArticles) { article in
                        ArticleRailCard(article: article) {
                            openArticles()
                        }
                    }
                }
            }
        }
    }

    /// 3 列网格的列定义（栏距 24 = `Layout.gridGutter`，对齐 1080 = 344×3 + 24×2）
    private var continueReadingColumns: [GridItem] {
        return Array(
            repeating: GridItem(.flexible(), spacing: Layout.gridGutter),
            count: 3
        )
    }

    /// 「快捷」：分组标题 + 3 枚胶囊（组件保留不动，只升格进分组）
    private var quickSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "快捷")
            QuickEntryRow(entries: quickEntries, onSelect: handleQuickEntry)
        }
    }

    // MARK: - 快捷入口

    private var quickEntries: [QuickEntry] {
        return [
            QuickEntry(id: 0, title: "全部文章", icon: "doc.text"),
            QuickEntry(id: 1, title: "光遇简报", icon: "bell.badge"),
            QuickEntry(id: 2, title: "关于", icon: "gearshape")
        ]
    }

    private func handleQuickEntry(_ entry: QuickEntry) {
        switch entry.id {
        case 0:
            openArticles()
        case 1:
            openBrief()
        default:
            showsSettings = true
        }
    }

    // MARK: - 派生数据

    /// 「继续读」的数据源：横滑 8 篇 / bento 3 列网格 6 篇（2 行 × 3）。
    ///
    /// 为什么不是全量：rail 是"看看还有什么"的入口，不是列表页；
    /// 全量塞进 `LazyHStack` 会让首帧多算几十个 `CoverArt`（每个都带 Canvas 噪点）。
    /// 宽档取 6 而不是 8：3 列网格里 8 篇会留一行只有 2 格的"半行"，比少两篇更显眼。
    private var continueReadingArticles: [ArticleSummary] {
        return Array(model.articles.prefix(metrics.usesRail ? 6 : 8))
    }

    /// 农历 / 节气副行：取不到就返回 nil，整行不占位（PRD §3.1 第 3 条）
    private var lunarText: String? {
        guard let brief = model.todayBrief else { return nil }
        guard let lunar = brief.lunar else { return nil }
        let trimmed = lunar.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var firstError: APIError? {
        if let error = model.feedState.error {
            return error
        }
        return model.briefState.error
    }

    /// PRD §5.2「离线（有缓存）」：手里有内容，但这次 feed 请求失败了（内容没被清空）。
    /// 不直接看 `feedState.error`：`.loaded` 与 `.failed` 互斥，有内容时它恒为 nil。
    private var showsOfflineBanner: Bool {
        return model.feedState.hasContent && model.lastFeedError != nil
    }

    // MARK: - 动作

    /// 倒计时卡点击 → 切到红石 Tab。
    ///
    /// 走现有的 `selectedTab` binding，**不新建导航栈**：根视图是条件渲染的 6 个页面 + 自绘 Tab 栏，
    /// 再塞一个 `NavigationStack` 会让 Tab 栏与页面层级打架。
    private func openRock() {
        withAnimation(Motion.tab) {
            selectedTab = .rock
        }
    }

    /// 简报轨迹卡 / 版本 tile 点击 → 切到简报 Tab
    private func openBrief() {
        withAnimation(Motion.tab) {
            selectedTab = .brief
        }
    }

    /// 天光卡点击 → 全屏打开天光页（3.11.0）。
    ///
    /// 不走 `withAnimation(Motion.tab)`：这不是切 Tab，是一次模态呈现 ——
    /// 给它套 Tab 的弹簧只会让"弹出"多一层与本页无关的位移。
    private func openSkyRoom() {
        showsSkyRoom = true
    }

    /// rail 卡 / 「全部文章」→ 切到文章 Tab。
    ///
    /// 文章详情是 `RootView` 的全屏覆盖，入口只接受 `ArticleSummary`；
    /// 首页没有详情入口（B 批次已删掉那套参数），所以这里落到列表页而不是"假装打开详情"。
    private func openArticles() {
        withAnimation(Motion.tab) {
            selectedTab = .articles
        }
    }
}

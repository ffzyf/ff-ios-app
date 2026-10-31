import SwiftUI

/// 红石小组件的底盘：**按地图换一张「意象背景」**（每个地图一套天色 + 一层独有剪影）。
///
/// ## 两条必须写下来的约束：为什么不能用照片
///
/// 用户的诉求是「看得出来自己在哪个地图」，最直觉的做法是放一张该地图的截图。两条硬约束把这条路封死：
/// 1. **Widget 里没有网络图**。小组件是独立进程 + 预渲染快照，`AsyncImage` 这类异步加载在出帧前
///    不保证完成；真要显示网络图就必须走 App Group 共享缓存落盘，而 `project.yml` 明确**不申请
///    App Group**（主 App 与 Widget 之间目前只有 URL Scheme 这一条单向契约）。没有合法的落图位置。
/// 2. **打包游戏截图有版权问题**，而且 6 张全屏图会把扩展体积从几十 KB 推到几 MB ——
///    小组件的内存预算（约 30 MB）和用户流量都不该花在这里。
///
/// 所以走第三条路：**用代码画意象**。矢量、任意尺寸清晰（158pt 的小号与 338pt 的中号共用同一份几何）、
/// 体积为零。每张图只有 2–4 个剪影元素 —— 小号里元素一多就糊成一团，这是刻意的克制。
///
/// ## 颜色：一个新 hex 都没造
///
/// - **底**一律取 `Theme.sky(_:)` 那七档手调的物理天空色（`SkyColors.top / horizon`），
///   再压一层 `Theme.bgBase` 的「纱」。纱是关键：`bgBase` 深色下近黑、浅色下米白，
///   所以同一行代码自动保证「深色下白字立得住 / 浅色下深字立得住」，
///   这个文件里**一个 `colorScheme` 都不用判**。
/// - **剪影**只用 `Theme.textPrimary` / `Theme.limeDeep` / `Theme.trackArc` 三个 token 的 `.opacity()`。
///   前两个在深浅两种外观下都与底色反向，天然有对比（浅色下是深灰剪影，深色下是浅浅的受光轮廓）。
/// - 唯一「品牌色当雾」的地方是雨林（`Theme.limeDeep` 补绿：`Theme.sky` 七档里没有绿色天空）
///   和伊甸（`Theme.badgeRed` 补暗红）。两处都只做**面**，不承载任何文字。
///
/// ## 与 App 内 `SkyGameBackdrop` 的关系
///
/// 同一套配方，但**必须重写一份**：Widget target 只编译 `Sources/Widget` + `Sources/Shared`，
/// DesignSystem 下的符号在小组件里不存在。
struct WidgetGameBackdrop: View {

    // MARK: - 数据

    /// 这张卡属于哪个地图的意象（由 `mapName` 解析出来）。
    ///
    /// 认不出的名字（空串 / `待确认` / 将来新增的地图）一律退化成 `.night` —— 也就是 V3.3
    /// 那块「静态的夜」，与旧版逐像素一致。**退化必须是"仍然好看"，不是"报错或空白"**。
    private let scene: MapScene

    /// `mapName` 形如 `"暮土·失落方舟"`；只看 `·` 之前的地名，点位名不参与配色。
    /// 默认值让调用方可以写 `WidgetGameBackdrop()`（等同默认夜）。
    init(mapName: String = "") {
        self.scene = MapScene(name: mapName)
    }

    // MARK: - 版式常量

    /// 星点位置（归一化坐标 + 尺寸 + 透明度）。
    ///
    /// 写死而不是随机：每次重绘都随机的话，刷新时星星会跳，看起来像画面在闪。
    /// 位置故意避开中上部（大字时刻与场次表都在那里），只做极淡的颗粒。
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.06, 0.12, 1.5, 0.20), (0.17, 0.30, 1.1, 0.14), (0.29, 0.09, 1.0, 0.13),
        (0.42, 0.24, 1.6, 0.20), (0.55, 0.13, 1.0, 0.13), (0.67, 0.33, 1.3, 0.16),
        (0.78, 0.07, 1.0, 0.12), (0.88, 0.22, 1.4, 0.18), (0.95, 0.40, 1.0, 0.12),
        (0.12, 0.58, 1.0, 0.10), (0.90, 0.62, 1.1, 0.10)
    ]

    /// 禁阁的额外星点（「星图」气质全靠密度，所以这一档多 7 颗、压在上半部）。
    private static let towerStars: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (0.10, 0.05, 0.9, 0.18), (0.22, 0.17, 1.2, 0.22), (0.36, 0.06, 0.8, 0.15),
        (0.47, 0.19, 1.0, 0.18), (0.61, 0.04, 1.3, 0.24), (0.72, 0.16, 0.9, 0.16),
        (0.84, 0.11, 1.1, 0.20)
    ]

    /// 云野的漂浮岛（x / y 归一化，width / height 占卡片比例）。三座就够，多则糊。
    private static let islands: [(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)] = [
        (0.28, 0.30, 0.20, 0.075),
        (0.68, 0.20, 0.14, 0.055),
        (0.86, 0.44, 0.10, 0.042)
    ]

    /// 雨林的高瘦树影（x / 顶部落点 / 宽度占比 / 不透明度）。
    /// 四根，高矮错开才像林。不透明度刻意比底部的绿雾(0.30)高一档：树要比"湿气"实，
    /// 否则深色下树干会糊进那团绿里，四根变成一片。
    private static let rainTrees: [(x: CGFloat, top: CGFloat, width: CGFloat, opacity: Double)] = [
        (0.08, 0.34, 0.055, 0.44),
        (0.22, 0.19, 0.040, 0.36),
        (0.80, 0.27, 0.050, 0.42),
        (0.93, 0.14, 0.034, 0.30)
    ]

    /// 雨林的斜雨丝（x / y / 长度占高比）。六道，方向统一（16°），才像同一阵雨。
    private static let rainStreaks: [(x: CGFloat, y: CGFloat, length: CGFloat)] = [
        (0.14, 0.62, 0.20), (0.32, 0.48, 0.16), (0.48, 0.72, 0.22),
        (0.64, 0.52, 0.18), (0.78, 0.66, 0.20), (0.90, 0.40, 0.15)
    ]

    /// 暮土的残破石柱（x / 顶部落点 / 宽度占比 / 倾斜角度）
    private static let ruinPillars: [(x: CGFloat, top: CGFloat, width: CGFloat, tilt: Double)] = [
        (0.12, 0.30, 0.055, -3.0),
        (0.30, 0.47, 0.038, 4.0),
        (0.86, 0.22, 0.048, 2.0)
    ]

    /// 禁阁的塔（x / 顶部落点 / 塔身宽度占比）。两根就够：细长塔楼再多会变栅栏。
    private static let towers: [(x: CGFloat, top: CGFloat, width: CGFloat)] = [
        (0.20, 0.24, 0.045),
        (0.76, 0.36, 0.036)
    ]

    /// 伊甸的尖利乱石（x / 宽 / 高 / 峰顶横向位置 / 不透明度）
    private static let voidSpikes: [(x: CGFloat, width: CGFloat, height: CGFloat, apexX: CGFloat, opacity: Double)] = [
        (0.18, 0.34, 0.44, 0.30, 0.22),
        (0.52, 0.26, 0.32, 0.62, 0.18),
        (0.84, 0.30, 0.36, 0.44, 0.20)
    ]

    /// 每个地图的物理天空档（`Theme.sky` 七档之一）。
    private var sky: Theme.SkyColors { Theme.sky(scene.skyPhase) }

    // MARK: - 主体

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                base(width: w, height: h)
                starField(width: w, height: h)
                haze(width: w, height: h)
                silhouettes(width: w, height: h)
                ambient(width: w, height: h)
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
    }

    // MARK: - ① 底（天色）

    /// 底层：物理天空色 + 一层「纱」。
    ///
    /// 纱的两段是「上浅下深」：卡的信息密度是三倍（大字时刻 / 倒计时 / 场次表 / 倍率），
    /// 而最碎的两行字压在最底部，所以底部要最暗（深色外观下），也最亮（浅色外观下）——
    /// `Theme.bgBase` 一次满足两种方向，不需要分支。
    @ViewBuilder
    private func base(width w: CGFloat, height h: CGFloat) -> some View {
        if scene == .night {
            // 默认夜：与 V3.3 逐像素一致（认不出的地图走这里，不允许有回归）
            LinearGradient(
                colors: [Theme.trackTop, Theme.trackBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            ZStack {
                LinearGradient(
                    colors: [sky.top, sky.horizon],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [
                        Theme.bgBase.opacity(scene.veil * 0.62),
                        Theme.bgBase.opacity(scene.veil)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    // MARK: - ② 星点

    /// 星点密度按地图调：云野/霞谷是白天与暖光，星星几乎看不见（`starGain` 压到 0.35）；
    /// 禁阁是「星图」，额外再撒一批（见 `towerStars`）。
    private func starField(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.stars.enumerated()), id: \.offset) { _, star in
                Circle()
                    .fill(Theme.trackArc.opacity(star.opacity * scene.starGain))
                    .frame(width: star.size, height: star.size)
                    .position(x: w * star.x, y: h * star.y)
            }
            if scene == .tower {
                ForEach(Array(Self.towerStars.enumerated()), id: \.offset) { _, star in
                    Circle()
                        .fill(Theme.trackArc.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(x: w * star.x, y: h * star.y)
                }
            }
        }
    }

    // MARK: - ③ 大气（每张地图的"那口气"）

    /// 每个地图一团气：亮雾 / 湿气 / 暖光 / 暗红。位置和色相就是「气质」本身。
    ///
    /// 全部走 `Theme.sky(...)` 里的 `top / horizon / edge` 或品牌 token 的 `.opacity()`，
    /// 光源方向统一从"画面里最亮的那处"往外扩，和 `SkyCard` 的大气光晕同一种画法。
    @ViewBuilder
    private func haze(width w: CGFloat, height h: CGFloat) -> some View {
        let radius = max(w, h)

        ZStack(alignment: .topLeading) {
            switch scene {
            case .night:
                // 左上角一层极淡的品牌色余晖：让深底不死板（旧版配方，逐像素保留）
                RadialGradient(
                    colors: [Theme.lime.opacity(0.10), Theme.lime.opacity(0)],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 180
                )
            case .cloudSea:
                // 云野：整片云海反着光，光从左上漫下来 —— 没有强光源，只有"发白"
                RadialGradient(
                    colors: [sky.edge.opacity(0.30), sky.edge.opacity(0)],
                    center: UnitPoint(x: 0.30, y: 0.12),
                    startRadius: 0,
                    endRadius: radius * 0.75
                )
            case .rainForest:
                // 雨林：暗绿的湿气沉在底部。`Theme.sky` 七档没有绿色天空，
                // 绿只能由品牌 `limeDeep` 补（只做雾，不承载文字）
                RadialGradient(
                    colors: [Theme.limeDeep.opacity(0.30), Theme.limeDeep.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.92),
                    startRadius: 0,
                    endRadius: radius * 0.85
                )
            case .canyon:
                // 霞谷：暖光雾落在谷底中央，就是两侧山脊之间那道落日
                RadialGradient(
                    colors: [sky.edge.opacity(0.34), sky.edge.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.46),
                    startRadius: 0,
                    endRadius: radius * 0.62
                )
            case .ruins:
                // 暮土：暗红雾贴地（`blueDusk` 的 top 就是那层暗红/绛紫）
                RadialGradient(
                    colors: [sky.top.opacity(0.36), sky.top.opacity(0)],
                    center: UnitPoint(x: 0.62, y: 0.88),
                    startRadius: 0,
                    endRadius: radius * 0.80
                )
            case .tower:
                // 禁阁：冷紫的天光从正上方压下来，塔影因此是逆光的
                RadialGradient(
                    colors: [sky.edge.opacity(0.26), sky.edge.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 0.10),
                    startRadius: 0,
                    endRadius: radius * 0.70
                )
            case .void:
                // 伊甸：地面上那圈危险的红光（`badgeRed` 是唯一够"警报"的红 token）
                RadialGradient(
                    colors: [Theme.badgeRed.opacity(0.30), Theme.badgeRed.opacity(0)],
                    center: UnitPoint(x: 0.52, y: 0.86),
                    startRadius: 0,
                    endRadius: radius * 0.72
                )
            }
        }
    }

    // MARK: - ④ 剪影（每个地图的"一眼认出"）

    /// 每个地图一层独有剪影。元素严格控制在 2–4 个：158pt × 158pt 里再多就不成形了。
    @ViewBuilder
    private func silhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch scene {
            case .night:
                // 默认夜只靠星点 + 云海，不加剪影（旧版没有，加了就是回归）
                EmptyView()
            case .cloudSea:
                islandSilhouettes(width: w, height: h)
            case .rainForest:
                rainForestSilhouettes(width: w, height: h)
            case .canyon:
                canyonSilhouettes(width: w, height: h)
            case .ruins:
                ruinsSilhouettes(width: w, height: h)
            case .tower:
                towerSilhouettes(width: w, height: h)
            case .void:
                voidSilhouettes(width: w, height: h)
            }
        }
    }

    /// 云野：两三座漂浮岛。岛面是扁椭圆，岛根是向下的尖 —— 一眼就能认出「浮着」。
    private func islandSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.islands.enumerated()), id: \.offset) { _, isle in
                Ellipse()
                    .fill(Theme.trackArc.opacity(0.34))
                    .frame(width: w * isle.width, height: h * isle.height)
                    .position(x: w * isle.x, y: h * isle.y)
                SilhouetteSpike(apexX: 0.5, apexY: 1, pointDown: true)
                    .fill(Theme.trackArc.opacity(0.20))
                    .frame(width: w * isle.width * 0.60, height: h * isle.height * 1.9)
                    .position(x: w * isle.x, y: h * (isle.y + isle.height * 1.05))
            }
        }
    }

    /// 雨林：高瘦树影（下粗上圆的细长胶囊）+ 六道统一 16° 的斜雨。
    private func rainForestSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.rainTrees.enumerated()), id: \.offset) { _, tree in
                Capsule()
                    .fill(Theme.limeDeep.opacity(tree.opacity))
                    .frame(width: w * tree.width, height: h * (1 - tree.top))
                    .position(x: w * tree.x, y: h * (tree.top + (1 - tree.top) / 2))
            }
            ForEach(Array(Self.rainStreaks.enumerated()), id: \.offset) { _, streak in
                Capsule()
                    .fill(Theme.trackArc.opacity(0.16))
                    .frame(width: 1, height: h * streak.length)
                    .rotationEffect(.degrees(16))
                    .position(x: w * streak.x, y: h * streak.y)
            }
        }
    }

    /// 霞谷：两侧山脊向中间收，中间留出落日的位置。
    private func canyonSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            CanyonRidge(peakX: 0.44, peakY: 0.34, fromLeft: true)
                .fill(Theme.textPrimary.opacity(0.15))
                .frame(width: w, height: h)
            CanyonRidge(peakX: 0.60, peakY: 0.46, fromLeft: false)
                .fill(Theme.textPrimary.opacity(0.21))
                .frame(width: w, height: h)
        }
    }

    /// 暮土：三根断裂石柱 + 一块倒下的残墙（"这里曾经是座城"）。
    private func ruinsSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.ruinPillars.enumerated()), id: \.offset) { _, pillar in
                Rectangle()
                    .fill(Theme.textPrimary.opacity(0.17))
                    .frame(width: w * pillar.width, height: h * (1 - pillar.top))
                    .rotationEffect(.degrees(pillar.tilt))
                    .position(x: w * pillar.x, y: h * (pillar.top + (1 - pillar.top) / 2))
            }
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.textPrimary.opacity(0.13))
                .frame(width: w * 0.30, height: h * 0.045)
                .rotationEffect(.degrees(-12))
                .position(x: w * 0.70, y: h * 0.945)
        }
    }

    /// 禁阁：两根细长塔楼 + 塔尖。窄到极致才像「阁」而不是「楼」。
    private func towerSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.towers.enumerated()), id: \.offset) { _, tower in
                let bodyRatio = (1 - tower.top) * 0.82
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.textPrimary.opacity(0.16))
                    .frame(width: w * tower.width, height: h * bodyRatio)
                    .position(x: w * tower.x, y: h * (tower.top + bodyRatio / 2))
                Capsule()
                    .fill(Theme.textPrimary.opacity(0.20))
                    .frame(width: max(1, w * tower.width * 0.22), height: h * (1 - tower.top) * 0.20)
                    .position(x: w * tower.x, y: h * (tower.top + (1 - tower.top) * 0.10))
            }
        }
    }

    /// 伊甸：三块尖利乱石。峰顶横向偏移各不相同，才不像"三个等腰三角形"。
    private func voidSilhouettes(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.voidSpikes.enumerated()), id: \.offset) { _, rock in
                SilhouetteSpike(apexX: rock.apexX, apexY: 0, pointDown: false)
                    .fill(Theme.textPrimary.opacity(rock.opacity))
                    .frame(width: w * rock.width, height: h * rock.height)
                    .position(x: w * rock.x, y: h * (1 - rock.height / 2))
            }
        }
    }

    // MARK: - ⑤ 前景（云海 / 浮尘 / 暖光）

    /// 最前面的一层：云野的云海、雨林的湿雾、暮土的浮尘，以及默认夜右下角那团暖光。
    ///
    /// 只给「有云 / 有雾」的地图铺云：霞谷、禁阁、伊甸是靠剪影撑气质的，压一层云会糊掉轮廓。
    @ViewBuilder
    private func ambient(width w: CGFloat, height h: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            switch scene {
            case .night:
                ForEach(0..<3, id: \.self) { layer in
                    cloudLayer(width: w, height: h, index: layer)
                }
                // 右下角的一团暖光（蜡烛 / 光的方向，也是红石的视觉暗示）—— 旧版配方
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.lime.opacity(0.18), Theme.lime.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 46
                        )
                    )
                    .frame(width: 92, height: 92)
                    .position(x: w * 0.86, y: h * 0.88)
            case .cloudSea:
                // 云野的云是被太阳照着的，所以比默认夜亮一档
                ForEach(0..<3, id: \.self) { layer in
                    cloudLayer(width: w, height: h, index: layer, boost: 1.5)
                }
            case .rainForest:
                ForEach(0..<2, id: \.self) { layer in
                    cloudLayer(width: w, height: h, index: layer, boost: 0.9)
                }
            case .ruins:
                // 荒土上浮着一层尘
                cloudLayer(width: w, height: h, index: 0, boost: 0.55)
            case .canyon, .tower, .void:
                EmptyView()
            }
        }
    }

    /// 一层云。
    ///
    /// 关键在 `.blur`：纯色椭圆直接叠会在边界留下硬边，浅色下看起来像"扫描线"。
    /// 模糊 12pt 之后边缘化开才像雾。颜色用 `trackArc`（淡蓝紫）而不是 `textPrimary`：
    /// 后者在浅色主题是深灰，压在白卡上就是一道道脏印子。
    private func cloudLayer(
        width w: CGFloat,
        height h: CGFloat,
        index: Int,
        boost: Double = 1
    ) -> some View {
        let baseY = 0.86 + CGFloat(index) * 0.06
        let opacity = (0.07 + Double(index) * 0.04) * boost
        let thickness = h * (0.22 - CGFloat(index) * 0.02)

        return ZStack {
            ForEach(Array(Self.cloudBumps.enumerated()), id: \.offset) { _, bump in
                Ellipse()
                    .fill(Theme.trackArc.opacity(opacity))
                    .frame(width: w * bump.width, height: thickness)
                    .position(x: w * bump.x, y: h * baseY + CGFloat(index) * 4)
            }
        }
        .blur(radius: 12)
        .allowsHitTesting(false)
    }

    /// 云朵形状（归一化 x / 宽度占比）。三个错开的椭圆就够看，不必画真云轮廓
    private static let cloudBumps: [(x: CGFloat, width: CGFloat)] = [
        (0.12, 0.46), (0.38, 0.58), (0.66, 0.52), (0.90, 0.40)
    ]
}

// MARK: - 地图意象

extension WidgetGameBackdrop {

    /// 一张卡的「地图意象」。名字是数据里 `map` 字段 `·` 之前的那一段。
    ///
    /// | 地图 | 气质 | 底色（`Theme.sky` 档） | 剪影 |
    /// |---|---|---|---|
    /// | 云野 | 明亮、云海、漂浮岛 | `day`（亮蓝）+ 0.60 纱 | 三座漂浮岛（椭圆 + 倒尖）+ 三层柔云 |
    /// | 雨林 | 湿润、高树、暗绿 | `night` + `limeDeep` 绿雾 | 四根高瘦树影 + 六道斜雨 |
    /// | 霞谷 | 暖橙、山谷、落日 | `sunset`（橙红）+ 0.54 纱 | 两侧山脊向中间收 + 谷底暖光雾 |
    /// | 暮土 | 荒芜、暗红、残破 | `blueDusk`（绛紫）+ 0.72 纱 | 三根断裂石柱 + 倒下的残墙 + 暗红雾 |
    /// | 禁阁 | 冷紫、塔、星图 | `blueDawn`（冷紫）+ 0.68 纱 | 两根细长塔楼 + 塔尖 + 更密的星点 |
    /// | 伊甸 | 深红黑、乱石、危险 | `sunset` 压到 0.80 纱（深红黑） | 三块尖利乱石 + 地面红光 |
    /// | 其他 | 认不出 → 旧版静态夜 | `trackTop/trackBottom` | 无（与 V3.3 逐像素一致） |
    enum MapScene {

        /// 云野
        case cloudSea
        /// 雨林
        case rainForest
        /// 霞谷
        case canyon
        /// 暮土
        case ruins
        /// 禁阁
        case tower
        /// 伊甸
        case void
        /// 默认夜（认不出的名字都退到这里）
        case night

        /// 从数据里的地图名认出意象。`"暮土·失落方舟"` → `.ruins`。
        init(name: String) {
            switch Self.family(of: name) {
            case "云野": self = .cloudSea
            case "雨林": self = .rainForest
            case "霞谷": self = .canyon
            case "暮土": self = .ruins
            case "禁阁": self = .tower
            case "伊甸": self = .void
            default: self = .night
            }
        }

        /// 取 `·` 之前的地名：`"暮土·失落方舟"` → `"暮土"`。
        ///
        /// 三种分隔符都认（`·` 是数据里的写法，`・` / `•` 是键盘打出来的近似字符，
        /// 玩家校准过的种子偶尔会混进来）；只有一个词（没有点位名）时原样返回。
        /// 空串 / `待确认` 都落进 `default` → `.night`，不会出现"空白卡"。
        static func family(of raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let head = trimmed
                .split(whereSeparator: { $0 == "·" || $0 == "・" || $0 == "•" })
                .first
                .map { String($0) } ?? trimmed
            return head.trimmingCharacters(in: .whitespaces)
        }

        /// 底色取 `Theme.sky` 的哪一档（七档都是手调过的物理天空色，不新造 hex）
        var skyPhase: SkyPhase {
            switch self {
            case .cloudSea: return .day
            case .rainForest: return .night
            case .canyon: return .sunset
            case .ruins: return .blueDusk
            case .tower: return .blueDawn
            case .void: return .sunset
            case .night: return .night
            }
        }

        /// 「纱」的浓度：压向 `Theme.bgBase` 的比例。
        ///
        /// 深色下 bgBase 近黑 → 数值越大越暗；浅色下 bgBase 米白 → 数值越大越亮。
        /// 也就是说这一个数同时决定"白字能不能读"和"深字能不能读"，
        /// 所以越亮的天色档要压得越狠（云野 0.60），越暗的可以放松（霞谷 0.54 只压一点）。
        var veil: Double {
            switch self {
            case .cloudSea: return 0.60
            case .rainForest: return 0.68
            case .canyon: return 0.54
            case .ruins: return 0.72
            case .tower: return 0.68
            case .void: return 0.80
            case .night: return 0.0   // 默认夜走 trackTop/trackBottom，不用纱
            }
        }

        /// 星点密度的倍数：白天与暖光地图几乎看不见，禁阁的"星图"要看得出密。
        var starGain: Double {
            switch self {
            case .cloudSea: return 0.40
            case .rainForest: return 0.80
            case .canyon: return 0.35
            case .ruins: return 0.90
            case .tower: return 1.20
            case .void: return 0.85
            case .night: return 1.0
            }
        }
    }
}

// MARK: - 剪影形状

/// 可调顶点的三角剪影。
///
/// 一个形状同时干两件事：
/// - `pointDown == false`：底边在地面、顶点朝上 → **尖石 / 山峰**（`apexX` 让峰顶左右偏，
///   三个等腰三角形排一起会像栅栏，必须错开）；
/// - `pointDown == true`：顶点朝下、底边在上 → **漂浮岛的岛根**（光遇里"浮着"的关键是那片收窄的底）。
///
/// 为什么自己画而不是用 `Triangle()`：`Shape` 一行 `Path` 就够，且能参数化；
/// 引入第三方库或为此新建一个文件都不值（本任务只允许改三个文件）。
private struct SilhouetteSpike: Shape {

    /// 顶点横向位置（0…1，相对自身宽度）
    var apexX: CGFloat = 0.5
    /// 顶点纵向位置：自顶算（`pointDown == false` 时是峰顶高度，
    /// `pointDown == true` 时是岛根尖到哪儿；传 1 = 一直收到 frame 底部）
    var apexY: CGFloat = 0
    /// 顶点是否朝下
    var pointDown: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let apex = CGPoint(
            x: rect.minX + rect.width * apexX,
            y: rect.minY + rect.height * apexY
        )

        if pointDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: apex)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: apex)
        }
        path.closeSubpath()
        return path
    }
}

/// 一侧山脊：从卡片某一侧的垂直边滑到中间，形成一个收进来的楔形。
///
/// 霞谷的「山谷」= 两个左右镜像的楔形，中间留出的空隙就是落日的位置。
/// 为什么不用 `LinearGradient` 叠一块深色：那会得到一条平直的斜线，
/// 而山脊必须有明确的一个"峰"（`peakX` / `peakY` 就是那个峰）。
private struct CanyonRidge: Shape {

    /// 峰的横向位置（0…1）
    var peakX: CGFloat
    /// 峰的高度（0…1，自顶算）
    var peakY: CGFloat
    /// 从左侧起坡（`false` = 从右侧起坡）
    var fromLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let peak = CGPoint(
            x: rect.minX + rect.width * peakX,
            y: rect.minY + rect.height * peakY
        )

        if fromLeft {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: peak.y))
            path.addLine(to: CGPoint(x: peak.x, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: peak.y))
            path.addLine(to: CGPoint(x: peak.x, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

import Foundation

/// 地图名的归一：把 `"暮土·失落方舟"` 切成 `"暮土"`。
///
/// ## 为什么这个文件只剩一个函数
///
/// 这里原本是 `WidgetGameBackdrop.swift`（639 行）：一套按地图换"意象背景"的矢量底盘
/// （天色渐变 + 星点 + 大气 + 云海 + 剪影，其中云层还带一层 12pt 的模糊）。
/// 红石卡改用 `RedstoneFace.swift` 里的 `RedstoneBackdrop`（3 停靠点渐变 + 纱 + 一团气 + 剪影）
/// 之后，那个 `View` 已经**没有任何调用点** —— 而 `.blur()` 是这套 Widget 语言明令禁止的一项
/// （R4：Widget 每帧重绘，离屏采样是这里最贵的一笔，且 12pt 半径与 11pt 字的字怀同量级，
/// 会把文字笔画吃进去）。留着一个没人调用的模糊实现，下一个人迟早会把它捡回去用。
/// 所以整块删掉：`struct WidgetGameBackdrop: View` 连同它专用的 `SilhouetteSpike` /
/// `CanyonRidge` 两个形状、星点表、云层函数、剪影函数一并删除。
///
/// 唯一被留下来的能力是**地名归一**：三种分隔符（`·` / `・` / `•`）的容错只该有一份实现，
/// 而 `RedstoneBackdrop.Band` 靠它把地图名翻成档位。文件名因此改成语义准确的 `MapScene.swift`
/// （xcodegen 按目录收集 `Sources/Widget/**/*.swift`，改名不影响工程配置）。
///
/// 原来的 `MapScene` 是个 `enum`，七个 case（`cloudSea` / `rainForest` / `…` / `night`）
/// 各自挂着 `skyPhase` / `veil` / `starGain` 三份配色参数。这些参数只服务于已删除的那个 View；
/// 档位配色现在由 `RedstoneBackdrop.Band` 唯一持有（一份档位表好过两份会各自漂移的表），
/// 所以 case 与那三个计算属性一并删除，只留这个命名空间和 `family(of:)`。
enum MapScene {

    /// 取 `·` 之前的地名：`"暮土·失落方舟"` → `"暮土"`。
    ///
    /// 三种分隔符都认（`·` 是数据里的写法，`・` / `•` 是键盘打出来的近似字符，
    /// 玩家校准过的种子偶尔会混进来）；只有一个词（没有点位名）时原样返回。
    /// 空串 / `待确认` 都返回原串，由调用方（`RedstoneBackdrop.Band.init(mapName:)`）
    /// 落进 `default` → `.unknown`，不会出现"空白卡"。
    static func family(of raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed
            .split(whereSeparator: { $0 == "·" || $0 == "・" || $0 == "•" })
            .first
            .map { String($0) } ?? trimmed
        return head.trimmingCharacters(in: .whitespaces)
    }
}

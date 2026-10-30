import SwiftUI

/// 月历网格位置的三种「没有格子」状态：加载中 / 本月未生成 / 请求失败。
///
/// 为什么单独成文件：`RockCalendarView` 已经承担"装配 + 翻月 + 折叠图 + 三张 sheet"，
/// 再塞三个状态分支会破单文件 250 行的约定（设计文档 §7.4）。这里只做长相，
/// 所有动作由调用方以闭包传入 —— 状态组件不持有 Store，也不发请求。
struct RockMonthStateView: View {
    /// 三种状态。`failed` 带上错误本身：文案（标题/副文案/图标）由 `APIError` 统一给，避免各页自造
    enum Mode: Equatable {
        case loading
        case empty
        case failed(APIError)
    }

    let mode: Mode
    /// 「查看规律」（空态的主按钮）
    var onShowRules: () -> Void = {}
    /// 「回到本月」；nil 表示当前就在本月，不显示这个次按钮
    var onReturnCurrent: (() -> Void)? = nil
    /// 失败态的重试
    var onRetry: () -> Void = {}

    var body: some View {
        switch mode {
        case .loading:
            skeleton
        case .empty:
            emptyBlock
        case .failed(let error):
            ErrorStateView(
                icon: error.icon,
                title: error.title,
                message: error.hint,
                onRetry: onRetry
            )
        }
    }

    // MARK: - 空

    private var emptyBlock: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                icon: "moon.stars",
                title: "本月排期尚未生成。",
                message: "排期排到这一月时，它会自己出现在这儿。想知道哪几天有场次，先看规律说明。"
            )
            HStack(spacing: 10) {
                Button {
                    Haptics.light()
                    onShowRules()
                } label: {
                    Text("查看规律")
                }
                .buttonStyle(PrimaryCTAStyle())

                if let onReturnCurrent = onReturnCurrent {
                    Button {
                        Haptics.selection()
                        onReturnCurrent()
                    } label: {
                        Text("回到本月")
                            .font(Typography.footnoteMedium)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    // MARK: - 骨架

    /// 7 列 × 5 行的小方块：与真实网格同高（56pt 格子），收起时不跳动
    private var skeleton: some View {
        VStack(spacing: 6) {
            SkeletonBlock(height: 12, cornerRadius: 4)
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 5) {
                    ForEach(0..<7, id: \.self) { _ in
                        SkeletonBlock(height: 56, cornerRadius: 10)
                    }
                }
            }
        }
        .accessibilityLabel("正在加载本月排期")
    }
}

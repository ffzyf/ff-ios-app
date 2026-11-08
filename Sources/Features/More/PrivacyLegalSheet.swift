import SwiftUI

/// 隐私政策 · 用户协议 · 免责声明（3.32.0）。
///
/// 为什么单独一个 sheet，而不是并进 `MoreAboutSheet`：
/// 「关于」回答的是"这个 App 是什么"（版本、数据来源、边界），一眼扫完；
/// 这里回答的是"我和你之间的权利边界"，长度差一个数量级。混在一页会把关于页撑成
/// 三千字长文，而关于页本该 10 秒看完。
///
/// 为什么正文是 `[LegalSection]` 常量而不是 Markdown 文件：
/// 本工程零第三方依赖，没有 Markdown 渲染器；写成结构体之后，目录与文案同源，
/// 改一条不用动排版，也顺手满足「隐私政策难以阅读（文字过小过密）」那条红线——
/// 字号走 `Typography.footnote` / `captionXS`，行高按 1.6 撑开。
///
/// **文案与工作区文档 `合规/隐私政策与用户协议.md` 同源，两处必须一起改。**
struct PrivacyLegalSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            PageBackground(glow: false)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    header
                    summaryCard
                    ForEach(LegalDocument.sections) { section in
                        sectionCard(section)
                    }
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.page)
                .padding(.top, 12)
                .padding(.bottom, Spacing.page)
            }
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - 骨架

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("隐私政策与声明")
                    .font(Typography.titleL)
                    .tracking(Typography.trackingLarge)
                    .foregroundStyle(Theme.textPrimary)
                Text("最后更新 \(LegalDocument.updatedAt)")
                    .font(Typography.captionXS)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            IconGlassButton(icon: "xmark", size: 36) {
                dismiss()
            }
            .accessibilityLabel("关闭")
        }
    }

    /// 顶部高亮块：这段是整页最该被看见的一句，放最前面。
    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("非官方工具 · 个人自用")
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)
                Text("本应用由个人开发并维护，不向公众提供商业服务。与网易公司（NetEase, Inc.）、thatgamecompany, Inc.（TGC）及其关联公司均不存在任何形式的隶属、合作、授权或关联关系，亦未获得上述任何一方的授权、许可或背书。")
                    .font(Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
            }
            .padding(Spacing.cardPadding)
        }
    }

    private func sectionCard(_ section: LegalSection) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(section.title)
                    .font(Typography.titleS)
                    .foregroundStyle(Theme.textPrimary)

                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, text in
                    Text(text)
                        .font(Typography.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                }

                ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, text in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textTertiary)
                        Text(text)
                            .font(Typography.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineSpacing(Typography.lineSpacing(fontSize: 13, multiple: 1.6))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.cardPadding)
        }
    }

    private var footer: some View {
        Text("继续使用本应用，即表示你已阅读并同意上述内容。若不同意，请卸载本应用。")
            .font(Typography.captionXS)
            .foregroundStyle(Theme.textTertiary)
            .lineSpacing(Typography.lineSpacing(fontSize: 11, multiple: 1.6))
            .padding(.horizontal, 4)
    }
}

// MARK: - 文案

struct LegalSection: Identifiable {
    let id: String
    let title: String
    var paragraphs: [String] = []
    var bullets: [String] = []
}

enum LegalDocument {
    static let updatedAt = "2026-11-09"

    static let sections: [LegalSection] = [
        LegalSection(
            id: "collect",
            title: "一、我们收集哪些信息",
            paragraphs: [
                "本应用没有账号注册体系，不收集姓名、手机号、邮箱、身份证号，不读取通讯录、相册与剪贴板。"
            ],
            bullets: [
                "位置：仅在你允许时用于查询当地天气与天文数据，随请求发送，不在服务端长期保存；拒绝后可在设置里手动选择城市。",
                "推送 Key（Bark）：由你自行填写，存放在 Cloudflare KV，回显时做掩码处理；不填则没有推送。",
                "AI 对话：你输入的提问与模型回复，用于生成回答与维持多轮上下文，存放在 Cloudflare D1。",
                "收益工作台登录态与站点访问口令：仅保存在本机 Keychain，标记为不进 iCloud 钥匙串、不进明文备份。",
                "界面偏好（主题、字号、折叠状态）：仅存本机。"
            ]
        ),
        LegalSection(
            id: "thirdparty",
            title: "二、第三方服务",
            paragraphs: ["依据《App 违法违规收集使用个人信息行为认定方法》关于逐一列明第三方的要求，本应用接入的第三方如下："],
            bullets: [
                "和风天气 QWeather：天气、预警、空气质量；接收城市坐标，不含个人身份。",
                "Open-Meteo：和风不可用时的天气兜底与日出日落；接收城市坐标。",
                "DeepSeek：大模型推理；接收你输入的对话内容。",
                "Cloudflare：接口托管与 KV / D1 存储。",
                "GitHub：版本数据下载，不含个人信息。",
                "以上第三方对其自身处理行为负责，其条款与隐私政策由各自制定。"
            ]
        ),
        LegalSection(
            id: "safety",
            title: "三、数据保存与保护",
            bullets: [
                "推送 Key 存放在 Cloudflare KV，回显时只显示首尾。",
                "AI 对话存放在 Cloudflare D1，仅用于维持上下文。",
                "登录凭据与访问口令存放在本机 Keychain，仅本机可用。",
                "本应用无账号体系，无法把数据精确归属到某个自然人，也就无法做针对单人的数据隔离。"
            ]
        ),
        LegalSection(
            id: "rights",
            title: "四、你的权利",
            bullets: [
                "撤回位置权限：系统设置 → 隐私与安全性 → 定位服务。",
                "删除推送 Key：在应用内设置里清空。",
                "删除全部本机数据：卸载本应用，Keychain 与本机存储随之清除。",
                "删除云端对话：在 AI 助手里删除会话，或联系开发者清除。"
            ]
        ),
        LegalSection(
            id: "ai",
            title: "五、AI 生成内容",
            paragraphs: [
                "AI 助手的回复由大语言模型生成，属于 AI 生成合成内容，可能不准确、不完整或带有偏差，不构成任何专业建议（包括医疗、法律、投资）。",
                "依据《生成式人工智能服务管理暂行办法》与《互联网信息服务深度合成管理规定》，界面内对这类内容作了标识；请勿将其作为事实依据。"
            ]
        ),
        LegalSection(
            id: "ip",
            title: "六、商标与知识产权",
            paragraphs: [
                "「网易」「光·遇」「Sky: Children of the Light」「thatgamecompany」「TGC」「和风天气」「QWeather」「DeepSeek」等名称、标识、商标的所有知识产权，均归各自权利人所有。本应用中的相关表述仅为数据来源与功能关联的说明，不代表取得任何授权。",
                "《光·遇》由 thatgamecompany, Inc. 开发，中国大陆地区版本由网易公司代理发行。"
            ]
        ),
        LegalSection(
            id: "disclaimer",
            title: "七、免责与责任限制",
            bullets: [
                "天气数据来自第三方，可能存在延迟、误差或中断，请勿用于飞行、航海、医疗等对准确性有要求的场景。",
                "AI 回答可能包含错误、过时或不完整的信息。",
                "版本与活动信息以游戏官方发布为准。",
                "本应用按「现状」提供，不作任何明示或默示担保；因使用或无法使用本应用造成的任何直接或间接损失，由使用者自行承担。"
            ]
        ),
        LegalSection(
            id: "license",
            title: "八、使用许可",
            bullets: [
                "授予你在自己拥有或控制的 Apple 设备上安装使用的非独占、不可转让、可撤销许可，仅供个人非商业用途。",
                "不得出售、出租、分发本应用或用于商业目的。",
                "不得绕过或破解访问控制（包括站点访问口令与发布口令）。",
                "不得批量抓取、缓存或再分发第三方数据。",
                "本应用不承诺长期可用性，开发者可随时调整或停止相关服务。"
            ]
        ),
        LegalSection(
            id: "minor",
            title: "九、未成年人",
            paragraphs: [
                "本应用不是面向未成年人的产品。若你是未成年人，请在监护人指导下使用，并避免填写任何个人信息。"
            ]
        ),
        LegalSection(
            id: "update",
            title: "十、政策更新",
            paragraphs: [
                "本政策随功能迭代更新，更新后直接替换页面旧版，不再单独通知；页面顶部「最后更新」日期同步变化。"
            ]
        )
    ]
}

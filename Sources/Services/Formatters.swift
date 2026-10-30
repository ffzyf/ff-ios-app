import Foundation

/// 时间展示规则（PRD §8.3）。
///
/// 两条硬约定：
/// 1. **一律北京时间（UTC+8）**，不跟随设备时区 —— 否则跨时区用户会看到「昨天的简报」；
/// 2. 所有相对时间都接受 `now` 参数，方便上层传入「服务端时间校正后」的当前时刻
///    （用响应的 `serverTime` 减本地时间得到 skew，避免设备时钟慢 5 分钟出现「-5 分钟前」）。
enum Formatters {
    /// 北京时间（UTC+8）
    static let beijing: TimeZone = TimeZone(secondsFromGMT: 8 * 3600) ?? TimeZone.current

    private static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = beijing
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    // MARK: - 相对时间（设计文档 §8.3 表格）

    /// < 60s 刚刚 / < 60min N 分钟前 / < 24h N 小时前 / < 7d N 天前 / 同年 10月28日 / 跨年 2025年10月28日
    static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "—" }
        let delta = now.timeIntervalSince(date)
        if delta < 0 {
            // 时钟偏差导致的「未来时间」，一律按刚刚处理，不显示负数
            return "刚刚"
        }
        if delta < 60 {
            return "刚刚"
        }
        if delta < 3600 {
            return "\(Int(delta / 60)) 分钟前"
        }
        if delta < 86_400 {
            return "\(Int(delta / 3600)) 小时前"
        }
        if delta < 7 * 86_400 {
            return "\(Int(delta / 86_400)) 天前"
        }
        return absoluteCN(date, now: now)
    }

    /// 今天 HH:mm / 昨天 HH:mm / N 天前 / yyyy-MM-dd
    static func relativeDay(_ date: Date?, now: Date = Date()) -> String {
        guard let date = date else { return "—" }
        let calendar = makeCalendar()
        if calendar.isDate(date, inSameDayAs: now) {
            return "今天 " + timeHHmm(date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + timeHHmm(date)
        }
        let startOfDate = calendar.startOfDay(for: date)
        let startOfNow = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0
        if days > 0 && days < 30 {
            return "\(days) 天前"
        }
        return isoDate(date)
    }

    // MARK: - 绝对时间

    /// 10月28日（同年）/ 2025年10月28日（跨年）
    static func absoluteCN(_ date: Date, now: Date = Date()) -> String {
        let calendar = makeCalendar()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        let currentYear = calendar.component(.year, from: now)
        if year != currentYear {
            return "\(year)年\(month)月\(day)日"
        }
        return "\(month)月\(day)日"
    }

    /// 10月30日 周四（首页大日期用）
    static func todayHeader(_ date: Date = Date()) -> String {
        let calendar = makeCalendar()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日 \(weekdayCN(date))"
    }

    /// 周四
    static func weekdayCN(_ date: Date) -> String {
        let calendar = makeCalendar()
        let index = calendar.component(.weekday, from: date) // 1 = 周日
        let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let safeIndex = min(max(index - 1, 0), names.count - 1)
        return names[safeIndex]
    }

    /// HH:mm（北京时间）
    static func timeHHmm(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = beijing
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// yyyy-MM-dd（北京时间）
    static func isoDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = beijing
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 服务端 `releaseDate` 是 date-only 字符串（`"2026-10-28"`），**不转 Date**，
    /// 直接按字符串拼成「10月28日」，避免时区把 28 号漂成 27 号。
    static func versionDateText(_ raw: String?) -> String {
        guard let raw = raw else { return "—" }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        let parts = trimmed.split(separator: "-")
        guard parts.count >= 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return trimmed
        }
        return "\(month)月\(day)日"
    }

    /// 问候语（PRD §3.1 第 1 条：概览首页问候行）
    static func greeting(_ date: Date = Date()) -> String {
        let calendar = makeCalendar()
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11:
            return "早上好"
        case 11..<13:
            return "中午好"
        case 13..<18:
            return "下午好"
        case 18..<23:
            return "晚上好"
        default:
            return "夜深了"
        }
    }
}

import Foundation

// MARK: - 轻量级本地埋点（无第三方依赖）

struct Analytics {

    private static let dateFormatter: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let writeQueue = DispatchQueue(label: "com.shootassist.analytics")

    // MARK: - 写入事件

    /// 记录一条事件，可附带任意属性
    static func track(_ event: String, properties: [String: Any] = [:]) {
        writeQueue.async {
            var events = UserDefaults.standard.array(forKey: "analytics_events") as? [[String: Any]] ?? []
            var eventData: [String: Any] = [
                "event": event,
                "timestamp": dateFormatter.string(from: Date())
            ]
            properties.forEach { eventData[$0.key] = $0.value }
            events.append(eventData)
            // 保留最近 500 条，避免 UserDefaults 膨胀
            if events.count > 500 { events = Array(events.suffix(500)) }
            UserDefaults.standard.set(events, forKey: "analytics_events")
        }
    }

    // MARK: - 读取统计

    /// 返回每个事件名的触发次数
    static func getStats() -> [String: Int] {
        let events = UserDefaults.standard.array(forKey: "analytics_events") as? [[String: Any]] ?? []
        var counts: [String: Int] = [:]
        events.forEach { event in
            if let name = event["event"] as? String {
                counts[name, default: 0] += 1
            }
        }
        return counts
    }

    /// 返回某个事件最近一次触发的时间（ISO 8601 字符串），没有则返回 nil
    static func lastOccurrence(of event: String) -> Date? {
        let events = UserDefaults.standard.array(forKey: "analytics_events") as? [[String: Any]] ?? []
        let formatter = ISO8601DateFormatter()
        return events
            .filter { $0["event"] as? String == event }
            .compactMap { $0["timestamp"] as? String }
            .compactMap { formatter.date(from: $0) }
            .max()
    }
}

// MARK: - 事件名常量（防止拼写错误）

extension Analytics {
    enum Event {
        // 核心启动
        static let appOpened             = "app_opened"

        // 拍同款漏斗
        static let cloneSessionStarted   = "clone_session_started"   // 进入拍同款模式
        static let referenceImagePicked  = "reference_image_picked"  // 选好参考图
        static let freeLimitReached      = "free_limit_reached"      // 免费次数用完

        // 照片/视频产出
        static let photoSaved            = "photo_saved"
        static let videoSaved            = "video_saved"
        static let comparisonCardShared  = "comparison_card_shared"  // 对比拼图分享
        static let videoShared           = "video_shared"            // 视频分享

        // 邀请裂变
        static let referralGenerated     = "referral_generated"      // 触发了分享（附带邀请码）

        // 付费漏斗
        static let paywallViewed         = "paywall_viewed"
        static let subscriptionPurchased = "subscription_purchased"
        static let subscriptionRestored  = "subscription_restored"
    }
}

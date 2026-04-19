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

// MARK: - 事件名常量（防止拼写错误 + 上线后统一漏斗口径）

extension Analytics {
    enum Event {
        // 核心启动 & onboarding
        static let appOpened             = "app_opened"
        static let onboardingShown       = "onboarding_shown"       // 首次启动 OnboardingView 出现
        static let onboardingPageViewed  = "onboarding_page_viewed" // 翻到某一页（properties: index）
        static let onboardingCompleted   = "onboarding_completed"   // 走完 3 页点开始使用
        static let onboardingSkipped     = "onboarding_skipped"     // 中途跳过（properties: at_page）

        // 权限
        static let permissionCameraGranted = "permission_camera_granted"
        static let permissionCameraDenied  = "permission_camera_denied"

        // 拍同款漏斗
        static let cloneSessionStarted   = "clone_session_started"   // 进入拍同款模式
        static let referenceImagePicked  = "reference_image_picked"  // 选好参考图
        static let freeLimitReached      = "free_limit_reached"      // 免费次数用完

        // 照片/视频产出
        static let photoSaved            = "photo_saved"
        static let videoSaved            = "video_saved"
        static let photoShared           = "photo_shared"            // 普通照片分享
        static let comparisonCardShared  = "comparison_card_shared"  // 对比拼图分享
        static let videoShared           = "video_shared"            // 视频分享

        // 姿势库
        static let poseLibraryOpened     = "pose_library_opened"     // 打开姿势库页面
        static let posePresetOpened      = "pose_preset_opened"      // 打开某个爆款姿势详情
        static let posePresetUsed        = "pose_preset_used"        // 点「用这个姿势拍」跳入相机
        static let posePresetCardShared  = "pose_preset_card_shared" // 点分享生成卡片成功

        // 邀请裂变
        static let referralShareFired    = "referral_share_fired"    // 触发了 shareAppendText 走分享
        static let referralRedeemed      = "referral_redeemed"       // 别人的码在本机兑换成功

        // 付费漏斗
        static let paywallViewed         = "paywall_viewed"
        static let paywallPlanSelected   = "paywall_plan_selected"   // 点选某个订阅档位
        static let paywallCtaTapped      = "paywall_cta_tapped"      // 点主 CTA 发起 StoreKit 购买
        static let paywallDismissed      = "paywall_dismissed"       // 未付费就关掉（放弃）
        static let trialGranted          = "trial_granted"           // 发了 N 天试用
        static let subscriptionPurchased = "subscription_purchased"
        static let subscriptionRestored  = "subscription_restored"
    }
}

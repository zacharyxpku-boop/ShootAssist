import Foundation
import Combine

// MARK: - 订阅管理（v1.0 全员免费版）
//
// v1.0 不接 StoreKit、不卖订阅。所有 Pro 闸 (isPro) 默认放行。
// 这样做是为了让首版尽快过审上线，绕开「付费协议+IAP 元数据+审核截图」这条慢链。
// 后续 v1.0.1 重新接回 StoreKit 时按 git history 还原即可。
//
// 保留对外接口（annualID/monthlyID 静态常量、isPro/products/trialEndDate 等
// @Published 属性、grantTrial 等方法），让 ReferralManager / SettingsView /
// HomeView / PaywallView 这些上层使用方零改动。

@MainActor
final class SubscriptionManager: ObservableObject {

    // 保留 Product ID 静态常量，给将来恢复订阅用，也避免引用 enum 报错
    static let annualID  = "com.shootassist.pro.annual"
    static let monthlyID = "com.shootassist.pro.monthly"

    /// v1.0 阶段全员视作 Pro：拍同款、画中画、对比卡、所有功能放行。
    @Published var isPro = true

    /// 邀请试用结束时间。v1.0 不依赖此值，但保留以便 SettingsView 显示。
    @Published var trialEndDate: Date? = nil

    /// 留接口给设置页显示「Pro 试用中，剩余 N 天」横条
    var trialDaysRemaining: Int {
        guard let end = trialEndDate else { return 0 }
        let secs = end.timeIntervalSinceNow
        guard secs > 0 else { return 0 }
        return Int(ceil(secs / 86_400))
    }

    init() {
        // 留一行欢迎日志，确认 v1.0 路径生效
        saLog("[SubscriptionManager] v1.0 free-for-all mode: isPro=true, no StoreKit")
    }

    // MARK: - 邀请试用（保留接口让 ReferralManager 调用不报错）
    /// 兑换邀请码时仍触发，仅本地标记一个到期日，让设置页/审核员看到「试用激活」反馈。
    /// v1.0 isPro 已经是 true，调不调没区别，但要让 UX 上给出确认。
    func grantTrial(days: Int) {
        let now = Date()
        let base = (trialEndDate.map { $0 > now ? $0 : now }) ?? now
        let newEnd = base.addingTimeInterval(TimeInterval(days) * 86_400)
        trialEndDate = newEnd
        // isPro 保持 true（已是 true）
        Analytics.track(Analytics.Event.trialGranted, properties: [
            "days": days,
            "v1_free_for_all": true
        ])
    }
}

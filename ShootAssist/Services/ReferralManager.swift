import Foundation

// MARK: - 邀请码管理
//
// 设计：
// - 本机邀请码：SA-XXXXXX 六位大写字母数字，首次调用时生成后持久化
// - 本机只能兑换一次（has_redeemed_code），避免重复白嫖试用
// - 兑换成功 → 被邀请人立即拿 7 天 Pro 试用；邀请人侧延时奖励依赖服务端，当前无后端故记 TODO
//
// UserDefaults keys：
//   referralCode            String  本机邀请码
//   referral_count          Int     本机分享/被邀请计数（老字段沿用）
//   has_redeemed_code       Bool    本机是否已兑换过别人的码
//   redeemed_code           String  具体兑换的是哪个码（排障用）

@MainActor
final class ReferralManager {

    static let shared = ReferralManager()

    enum RedeemResult: Equatable {
        case success              // 兑换成功，已发放 7 天试用
        case alreadyRedeemed      // 本机已兑换过，一机一次
        case ownCode              // 不能用自己的码
        case invalidFormat        // 格式不对（非 SA-XXXXXX）
    }

    // MARK: - 邀请码生成 / 读取（静态保留，旧调用点兼容）
    // 标 nonisolated 让 PhotoModeView / ComparisonCardService 在非主线程也能直接调。

    /// 获取（或生成）本机邀请码，格式：SA-XXXXXX
    nonisolated static func getReferralCode() -> String {
        if let existing = UserDefaults.standard.string(forKey: "referralCode") {
            return existing
        }
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let code = "SA-" + String((0..<6).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(code, forKey: "referralCode")
        return code
    }

    /// 带邀请码的分享文案，拼接在照片/视频分享文字末尾（纯函数，不记录分享次数）
    nonisolated static func shareAppendText() -> String {
        let code = getReferralCode()
        return "\n用小白快拍拍出同款 邀请码: \(code)"
    }

    /// 记录一次分享动作（调用 shareAppendText 时自动触发）
    nonisolated static func recordShareAction() {
        let count = UserDefaults.standard.integer(forKey: "referral_count")
        UserDefaults.standard.set(count + 1, forKey: "referral_count")
        Analytics.track(Analytics.Event.referralShareFired)
    }

    // MARK: - 兑换别人的邀请码

    /// 本机是否已经兑换过别人的邀请码
    var hasRedeemedCode: Bool {
        UserDefaults.standard.bool(forKey: "has_redeemed_code")
    }

    /// 兑换邀请码，成功则给被邀请人发 7 天 Pro 试用
    ///
    /// - 边界：
    ///   1. 格式错误（非 SA-XXXXXX）→ .invalidFormat
    ///   2. 等于自己的码 → .ownCode
    ///   3. 本机已兑换过 → .alreadyRedeemed
    ///   4. 其余全部视为 .success，发 7 天试用
    ///
    /// - TODO: 上线云端后，被邀请人兑换成功需回调邀请人端 grantTrial(days: 7) 实现双向奖励；
    ///   当前无后端，邀请人只能通过本机 referral_count 看到「多少朋友用了我的码」。
    func redeem(code: String, subManager: SubscriptionManager) -> RedeemResult {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        // 1. 格式校验：SA- 开头 + 6 位字母数字
        guard isValidFormat(normalized) else {
            return .invalidFormat
        }

        // 2. 自邀拦截
        if normalized == Self.getReferralCode() {
            return .ownCode
        }

        // 3. 一机一次
        if hasRedeemedCode {
            return .alreadyRedeemed
        }

        // 4. 成功：落标 + 发试用 + 本地计数（给邀请人端看到「有人用我的码了」的近似感知）
        UserDefaults.standard.set(true, forKey: "has_redeemed_code")
        UserDefaults.standard.set(normalized, forKey: "redeemed_code")
        subManager.grantTrial(days: 7)

        let count = UserDefaults.standard.integer(forKey: "referral_count")
        UserDefaults.standard.set(count + 1, forKey: "referral_count")

        // 试用到期前 24h 本地推送：先问授权（未定），再排单
        if let trialEnd = subManager.trialEndDate {
            Task {
                await TrialNotificationScheduler.shared.requestAuthIfNeeded()
                TrialNotificationScheduler.shared.scheduleTrialExpiryReminder(trialEnd: trialEnd)
            }
        }

        Analytics.track(Analytics.Event.referralRedeemed, properties: ["code": normalized])
        return .success
    }

    private func isValidFormat(_ code: String) -> Bool {
        // SA- 前缀 + 6 位大写字母/数字
        let pattern = #"^SA-[A-Z0-9]{6}$"#
        return code.range(of: pattern, options: .regularExpression) != nil
    }
}

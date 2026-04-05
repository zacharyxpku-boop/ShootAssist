import Foundation

// MARK: - 邀请码管理

struct ReferralManager {

    /// 获取（或生成）本机邀请码，格式：SA-XXXXXX
    static func getReferralCode() -> String {
        if let existing = UserDefaults.standard.string(forKey: "referralCode") {
            return existing
        }
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let code = "SA-" + String((0..<6).map { _ in chars.randomElement()! })
        UserDefaults.standard.set(code, forKey: "referralCode")
        return code
    }

    /// 带邀请码的分享文案，拼接在照片/视频分享文字末尾（纯函数，不记录分享次数）
    static func shareAppendText() -> String {
        let code = getReferralCode()
        return "\n用小白快门拍出同款 📸 邀请码: \(code)"
    }

    /// 记录一次分享动作（调用 shareAppendText 时自动触发）
    static func recordShareAction() {
        let count = UserDefaults.standard.integer(forKey: "referral_count")
        UserDefaults.standard.set(count + 1, forKey: "referral_count")
    }
}

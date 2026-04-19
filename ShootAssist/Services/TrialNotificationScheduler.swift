import Foundation
import UserNotifications

// MARK: - 试用到期前 24h 本地推送
//
// 目的：邀请码兑换的 7 天试用即将到期前 24h，弹一条本地通知，引导用户转年订阅。
// 纯本地：用 UNCalendarNotificationTrigger + 固定 identifier，不依赖服务器。
//
// identifier 约定：
//   "trial_expiry_24h"   —— 同一用户只会有一条 pending，重复排单前先 remove 去重
//
// 边界：
//   - 权限被拒：不崩，不重复弹授权，什么都不干（下次冷启动也不会再问）
//   - 兑换时剩余 < 24h：不排（触发时间已过）
//   - 真付费：调 cancelTrialExpiryReminder() 撤掉，避免付费用户被骚扰

@MainActor
final class TrialNotificationScheduler {

    static let shared = TrialNotificationScheduler()

    private static let identifier = "trial_expiry_24h"
    private let center = UNUserNotificationCenter.current()

    private init() {}

    /// 请求通知授权。已授权/已拒绝都直接返回，不重复弹。
    func requestAuthIfNeeded() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                saLog("[TrialNotif] requestAuthorization failed: \(error.localizedDescription)")
            }
        case .denied, .authorized, .provisional, .ephemeral:
            // 拒绝不再骚扰；已授权无需再问
            return
        @unknown default:
            return
        }
    }

    /// 排一条「到期前 24h」的本地通知。
    /// - 先去重同 identifier 的 pending
    /// - 若 triggerDate 已过（剩余 < 24h），直接跳过
    func scheduleTrialExpiryReminder(trialEnd: Date) {
        // 去重：任何旧的 pending 先撤掉
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])

        let triggerDate = trialEnd.addingTimeInterval(-86_400)
        guard triggerDate > Date() else {
            saLog("[TrialNotif] skip: triggerDate already passed (trialEnd=\(trialEnd))")
            return
        }

        // 授权状态二次兜底：未授权就不排，省得留个永远不会亮的 pending
        Task { [center] in
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
                saLog("[TrialNotif] skip: not authorized (\(settings.authorizationStatus.rawValue))")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Pro 试用还剩 1 天"
            content.body = "年订阅现在锁定，体验不中断"
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                saLog("[TrialNotif] scheduled at \(triggerDate)")
            } catch {
                saLog("[TrialNotif] add failed: \(error.localizedDescription)")
            }
        }
    }

    /// 撤销 pending 的到期提醒。真付费或试用主动取消时调。
    func cancelTrialExpiryReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}

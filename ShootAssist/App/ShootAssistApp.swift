import SwiftUI

@main
struct ShootAssistApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @StateObject private var subManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.light)
                .environmentObject(subManager)
                .onAppear {
                    Analytics.track(Analytics.Event.appOpened)
                    // 清理上次 session 残留的临时文件
                    Self.cleanTempFiles()
                    // 安全网：冷启动若试用剩余 >24h，重排到期前 24h 提醒
                    // （覆盖 App 被删除/重装、系统清 pending 等边缘场景）
                    Task { [subManager] in
                        if let trialEnd = subManager.trialEndDate,
                           trialEnd.timeIntervalSinceNow > 86_400 {
                            await TrialNotificationScheduler.shared.requestAuthIfNeeded()
                            TrialNotificationScheduler.shared.scheduleTrialExpiryReminder(trialEnd: trialEnd)
                        }
                    }
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasSeenOnboarding },
                        set: { showing in
                            if !showing { hasSeenOnboarding = true }
                        }
                    ))
                }
        }
    }

    /// 清理 tmp 目录中 sa_ 前缀的残留文件（视频/音频/水印缓存）
    private static func cleanTempFiles() {
        DispatchQueue.global(qos: .utility).async {
            let tmp = FileManager.default.temporaryDirectory
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: [.creationDateKey]
            ) else { return }
            let prefixes = ["sa_video_", "sa_audio_", "sa_wm_", "sa_lyric_clip_", "sa_import_"]
            for file in files where prefixes.contains(where: { file.lastPathComponent.hasPrefix($0) }) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

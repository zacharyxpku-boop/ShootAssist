import SwiftUI
import AVFoundation

/// 视频模式 ViewModel — 仅负责画中画参考视频 + 倒计时延时。
/// 历史版本的对口型 / 歌词识别 / Vision 骨架在 v1.0 被砍，
/// 那些代码放在 git 历史里，想回滚就 checkout。
class VideoModeViewModel: ObservableObject {
    @Published var selectedDelay: DelayOption = .three
    @Published var isCountingDown = false
    @Published var countdownValue = 3

    // MARK: - 画中画参考视频
    @Published var referenceVideoURL: URL?
    @Published var isPiPPlaying: Bool = false
    @Published var showVideoPicker = false
    /// 每次递增都会让 PiP 跳到 0 重新播放（录制真正开始时调用）
    @Published var pipRestartToken: Int = 0
    /// 是否解除 PiP 自带音轨静音 — false 时静止预览不出声，
    /// true 时录制开始让用户跟着原音乐节奏跳舞
    @Published var pipAudioEnabled: Bool = false

    private var countdownTimer: Timer?

    // MARK: - 画中画控制

    func importReferenceVideo(url: URL) {
        referenceVideoURL = url
        // 导入后停在第一帧：用户需要点开始拍摄才播放，保证和相机录制同步起拍
        isPiPPlaying = false
        pipAudioEnabled = false  // 预览阶段不出声
        pipRestartToken += 1  // 触发 PiPView 重置到 0，显示第一帧作为封面
    }

    func clearReferenceVideo() {
        isPiPPlaying = false
        pipAudioEnabled = false
        referenceVideoURL = nil
    }

    /// 正式录制开始的瞬间调用 — seek 到 0 + 从头播放 + 解除音轨静音
    /// 让背景音乐和相机录制同步起拍，麦克风顺带录到音乐做后期参考
    func startPiPPlaybackSynced() {
        guard referenceVideoURL != nil else { return }
        // 切换到 playAndRecord 类别，否则 AVCaptureSession 会强制独占音频
        // 导致 AVPlayer 静音播放
        activatePlaybackRecordSession()
        pipAudioEnabled = true
        isPiPPlaying = true
        pipRestartToken += 1  // 递增 token 让 PiPVideoView 执行 seek(.zero)+play
    }

    /// 录制停止时暂停参考视频
    func stopPiPPlayback() {
        isPiPPlaying = false
        pipAudioEnabled = false
    }

    /// 切到 .playAndRecord，让 PiP AVPlayer 在录制期间也能出声。
    /// 幂等：若当前 category/mode/options 已一致就跳过 setCategory，避免 AVCaptureSession
    /// 正在跑时 setCategory 触发 AVCaptureSessionWasInterrupted 通知（系统把它当成
    /// audioDeviceInUseByAnotherClient），导致录制中音频突然静音或 session 自重启。
    private func activatePlaybackRecordSession() {
        let session = AVAudioSession.sharedInstance()
        let wantCategory: AVAudioSession.Category = .playAndRecord
        let wantMode: AVAudioSession.Mode = .videoRecording
        let wantOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
        let alreadyCorrect = session.category == wantCategory
            && session.mode == wantMode
            && session.categoryOptions == wantOptions
        do {
            if !alreadyCorrect {
                try session.setCategory(wantCategory, mode: wantMode, options: wantOptions)
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            saLog("[VideoMode] activatePlaybackRecordSession failed: \(error)")
        }
    }

    /// 录制结束后让别的 App 恢复音频
    func deactivateAudioSessionIfIdle() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 延时倒计时

    func startCountdown(completion: @escaping () -> Void) {
        guard selectedDelay != .none else { completion(); return }
        cancelCountdown()
        isCountingDown = true
        countdownValue = selectedDelay.rawValue
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            DispatchQueue.main.async {
                self.countdownValue -= 1
                if self.countdownValue <= 0 {
                    timer.invalidate(); self.countdownTimer = nil; self.isCountingDown = false
                    completion()
                }
            }
        }
    }

    func cancelCountdown() {
        countdownTimer?.invalidate(); countdownTimer = nil; isCountingDown = false
    }

    func cycleDelay() {
        let all = DelayOption.allCases
        if let idx = all.firstIndex(of: selectedDelay) {
            selectedDelay = all[(all.distance(from: all.startIndex, to: idx) + 1) % all.count]
        }
    }

    deinit {
        countdownTimer?.invalidate()
    }
}

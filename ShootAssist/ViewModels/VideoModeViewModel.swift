import SwiftUI
import Vision
import AVFoundation
import Combine
import Speech

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

    // MARK: - 对口型歌词（预设）
    @Published var selectedSong: SongLyrics = lyricDatabase[0]
    @Published var currentLyricIndex = 0
    @Published var showSongSelector = false
    @Published var simulatedPlaybackTime: TimeInterval = 0

    // MARK: - 对口型：用户自定义音乐
    @Published var customMusicURL: URL?
    @Published var customMusicName: String = ""
    @Published var isRecognizingLyrics: Bool = false
    @Published var customSongLyrics: SongLyrics?
    @Published var lyricRecognitionError: String?
    @Published var showAudioPicker: Bool = false

    // MARK: - 对口型：从视频提取音频
    @Published var showVideoPickerForLipSync: Bool = false
    @Published var isExtractingVideoAudio: Bool = false

    /// 当前生效的歌曲（自定义优先）
    var activeSong: SongLyrics { customSongLyrics ?? selectedSong }

    // MARK: - Vision 实时关键点
    @Published var liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    private var countdownTimer: Timer?
    private var lyricTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lipSyncAudioPlayer: AVAudioPlayer?

    // MARK: - 绑定 VisionService

    func bindVision(_ visionService: VisionService) {
        cancellables.removeAll()
        visionService.$bodyJoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in self?.liveJoints = joints }
            .store(in: &cancellables)
    }

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

    // MARK: - 自定义音乐导入 & 歌词识别

    func importCustomAudio(url: URL) {
        customMusicURL = url
        customMusicName = url.deletingPathExtension().lastPathComponent
        isRecognizingLyrics = true
        lyricRecognitionError = nil
        customSongLyrics = nil

        Task {
            let lines = await LyricRecognitionService.shared.recognizeLyrics(from: url)
            await MainActor.run {
                self.isRecognizingLyrics = false
                if lines.isEmpty {
                    self.lyricRecognitionError = "未识别到歌词，将显示节拍提示"
                    let beatLines: [LyricLine] = (0..<30).map { i in
                        LyricLine(text: "\u{266A}  \u{266A}  \u{266A}",
                                  startTime: Double(i) * 2.0,
                                  endTime:   Double(i) * 2.0 + 2.0)
                    }
                    self.customSongLyrics = SongLyrics(songName: self.customMusicName,
                                                       artist: "自定义",
                                                       lines: beatLines)
                } else {
                    self.customSongLyrics = SongLyrics(songName: self.customMusicName,
                                                       artist: "自定义",
                                                       lines: lines)
                }
                self.stopLyricScroll()
                self.startLyricScroll()
            }
        }
    }

    /// 从本地视频提取音频，走歌词识别流程
    func importVideoForLipSync(asset: AVAsset) {
        isExtractingVideoAudio = true
        lyricRecognitionError = nil
        Task {
            let audioURL = await Self.extractAudio(from: asset)
            await MainActor.run {
                self.isExtractingVideoAudio = false
                if let url = audioURL {
                    self.importCustomAudio(url: url)
                } else {
                    self.lyricRecognitionError = "无法读取这个视频的音频，换一个带音乐的视频试试"
                }
            }
        }
    }

    /// 从视频中提取音频（原 VideoAnalysisService.extractAudio 移入此处）
    private static func extractAudio(from asset: AVAsset) async -> URL? {
        guard (try? await asset.loadTracks(withMediaType: .audio).first) != nil else { return nil }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_audio_\(Int(Date().timeIntervalSince1970)).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { return nil }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        await exportSession.export()

        return exportSession.status == .completed ? outputURL : nil
    }

    func clearCustomMusic() {
        customMusicURL = nil
        customMusicName = ""
        customSongLyrics = nil
        lyricRecognitionError = nil
        stopLipSyncAudio()
        stopLyricScroll()
    }

    // MARK: - 对口型音频播放

    func startLipSyncAudio() {
        guard let url = customMusicURL else { return }
        // 同 activatePlaybackRecordSession 的幂等思路：若 AVCaptureSession 正在跑，
        // mid-flight setCategory 会触发 interruption 导致录制音频异常
        let session = AVAudioSession.sharedInstance()
        let wantCategory: AVAudioSession.Category = .playAndRecord
        let wantOptions: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
        do {
            if session.category != wantCategory || session.categoryOptions != wantOptions {
                try session.setCategory(wantCategory, mode: .default, options: wantOptions)
            }
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lipSyncAudioPlayer = try? AVAudioPlayer(contentsOf: url)
            self.lipSyncAudioPlayer?.prepareToPlay()
            self.lipSyncAudioPlayer?.play()
        }
    }

    func stopLipSyncAudio() {
        let wasPlaying = lipSyncAudioPlayer?.isPlaying ?? false
        lipSyncAudioPlayer?.stop()
        lipSyncAudioPlayer = nil
        if wasPlaying { deactivateAudioSessionIfIdle() }
    }

    func deactivateAudioSessionIfIdle() {
        guard !(lipSyncAudioPlayer?.isPlaying ?? false) else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 歌词滚动

    private var lyricStartDate: Date?

    func startLyricScroll() {
        stopLyricScroll()
        currentLyricIndex = 0
        simulatedPlaybackTime = 0
        lyricStartDate = Date()
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let startDate = self.lyricStartDate else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            self.simulatedPlaybackTime = elapsed
            let lines = self.activeSong.lines
            let newIndex = lines.lastIndex(where: { $0.startTime <= elapsed }) ?? 0
            if newIndex != self.currentLyricIndex {
                withAnimation(.easeInOut(duration: 0.3)) { self.currentLyricIndex = newIndex }
            }
            if let last = lines.last, elapsed > last.endTime + 1.0 {
                self.lyricStartDate = Date()
                self.simulatedPlaybackTime = 0
                self.currentLyricIndex = 0
            }
        }
    }

    func stopLyricScroll() {
        lyricTimer?.invalidate()
        lyricTimer = nil
        simulatedPlaybackTime = 0
        lyricStartDate = nil
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
        lyricTimer?.invalidate()
        lipSyncAudioPlayer?.stop()
        cancellables.removeAll()
    }
}

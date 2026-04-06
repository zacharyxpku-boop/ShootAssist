import SwiftUI
import Vision
import AVFoundation
import Combine
import Speech

class VideoModeViewModel: ObservableObject {
    @Published var currentSubMode: VideoSubMode = .videoTemplate
    @Published var selectedDelay: DelayOption = .three
    @Published var isCountingDown = false
    @Published var countdownValue = 3

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

    // MARK: - 跟拍手势舞（视频模版）
    @Published var showVideoPicker = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var importedTemplate: AnalyzedTemplate? = nil
    @Published var templateMoveIndex: Int = 0
    @Published var isTemplatePlaybackActive = false
    @Published var analysisErrorMessage: String? = nil

    // MARK: - Demo 模板（免费体验，每日10次）
    @Published var isDemoMode: Bool = false
    @Published var currentDemoEntry: DemoEntry? = nil
    @Published var showPostDemoBanner: Bool = false

    static let freeDanceLimitPerDay = 10
    @AppStorage("sa_dance_date")  private var danceDateStr: String = ""
    @AppStorage("sa_dance_count") private var danceCount: Int = 0

    var freeDanceRemaining: Int {
        let today = Self.todayString()
        if danceDateStr != today { return Self.freeDanceLimitPerDay }
        return max(0, Self.freeDanceLimitPerDay - danceCount)
    }

    func recordDanceUse() {
        let today = Self.todayString()
        if danceDateStr != today { danceDateStr = today; danceCount = 0 }
        danceCount += 1
    }

    func isDanceLimitReached(isPro: Bool) -> Bool {
        guard !isPro else { return false }
        return freeDanceRemaining <= 0
    }

    private static func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // MARK: - Vision 实时关键点（从 CameraViewModel 传入）
    @Published var liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    private var countdownTimer: Timer?
    private var lyricTimer: Timer?
    private var templateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?       // 手势舞模板音频
    private var lipSyncAudioPlayer: AVAudioPlayer? // 对口型自定义音频
    private var templateGeneration: Int = 0

    // MARK: - 绑定 VisionService

    func bindVision(_ visionService: VisionService) {
        cancellables.removeAll()
        visionService.$bodyJoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in self?.liveJoints = joints }
            .store(in: &cancellables)
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
                        LyricLine(text: "♪  ♪  ♪",
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
                // 用新歌词重启预览滚动
                self.stopLyricScroll()
                self.startLyricScroll()
            }
        }
    }

    /// 从本地视频提取音频后，走和音频上传相同的歌词识别流程
    func importVideoForLipSync(asset: AVAsset) {
        isExtractingVideoAudio = true
        lyricRecognitionError = nil
        Task {
            let audioURL = await VideoAnalysisService.shared.extractAudioForLipSync(from: asset)
            await MainActor.run {
                self.isExtractingVideoAudio = false
                if let url = audioURL {
                    self.importCustomAudio(url: url)
                } else {
                    self.lyricRecognitionError = "视频音频提取失败，请换一个视频文件"
                }
            }
        }
    }

    func clearCustomMusic() {
        customMusicURL = nil
        customMusicName = ""
        customSongLyrics = nil
        lyricRecognitionError = nil
        stopLipSyncAudio()
        stopLyricScroll()   // 必须先停，防止 currentLyricIndex 越界访问新 lines
        // 由调用方（sheet onDisappear）决定是否重启 startLyricScroll
    }

    // MARK: - 对口型音频播放（录制期间同步播放）

    func startLipSyncAudio() {
        guard let url = customMusicURL else { return }
        do {
            // playAndRecord + mixWithOthers：允许麦克风录音同时播放音乐，不互斥
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true,
                options: .notifyOthersOnDeactivation)
        } catch { return }
        // AVAudioPlayer 的 prepareToPlay/play 必须在主线程调用
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

    // MARK: - 导入视频并分析（含 90s 超时保护；成功后记录一次使用）

    func importAndAnalyzeVideo(asset: AVAsset) {
        analysisGeneration += 1
        let gen = analysisGeneration   // 捕获本次代；旧任务完成时 gen 不匹配则丢弃
        isAnalyzing = true
        analysisProgress = 0
        importedTemplate = nil
        analysisErrorMessage = nil

        Task {
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                await MainActor.run {
                    guard !Task.isCancelled, self.analysisGeneration == gen else { return }
                    self.isAnalyzing = false
                    self.analysisErrorMessage = "分析超时，请选择较短的视频（建议 60s 内）"
                }
            }

            let template = await VideoAnalysisService.shared.analyzeVideo(
                asset: asset,
                sampleInterval: 0.2
            ) { [weak self] progress in
                DispatchQueue.main.async {
                    guard self?.analysisGeneration == gen else { return }
                    self?.analysisProgress = progress
                }
            }

            timeoutTask.cancel()

            await MainActor.run {
                // gen 不匹配说明已有新的分析任务覆盖，旧结果直接丢弃
                guard self.analysisGeneration == gen else { return }
                self.isAnalyzing = false
                if template.duration <= 0 {
                    self.analysisErrorMessage = "无法读取视频，请换一个视频文件"
                } else if template.emojiMoves.isEmpty {
                    self.importedTemplate = template
                    self.analysisErrorMessage = "未检测到明显手势，建议选人物清晰的舞蹈视频"
                } else {
                    self.recordDanceUse()
                    self.importedTemplate = template
                }
            }
        }
    }

    // MARK: - 跟拍播放控制

    func startTemplatePlayback() {
        stopTemplatePlayback()
        guard let template = importedTemplate, !template.emojiMoves.isEmpty else { return }

        templateGeneration += 1
        let gen = templateGeneration
        templateMoveIndex = 0
        isTemplatePlaybackActive = true

        // 录制时需要 playAndRecord + mixWithOthers，才能边录视频边播放模板音乐
        // 否则 AVCaptureMovieFileOutput 会独占音频会话导致 AVAudioPlayer 无声
        if template.audioURL != nil {
            do {
                try AVAudioSession.sharedInstance().setCategory(
                    .playAndRecord,
                    mode: .default,
                    options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
                )
                try AVAudioSession.sharedInstance().setActive(
                    true, options: .notifyOthersOnDeactivation)
            } catch {}
        }

        // AVAudioPlayer 必须在主线程创建和播放
        if let audioURL = template.audioURL {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.templateGeneration == gen else { return }
                self.audioPlayer = try? AVAudioPlayer(contentsOf: audioURL)
                self.audioPlayer?.prepareToPlay()
                self.audioPlayer?.play()
            }
        }

        scheduleTemplateMove(at: 0, moves: template.emojiMoves, generation: gen)
    }

    private func scheduleTemplateMove(at index: Int, moves: [EmojiMove], generation: Int) {
        guard index < moves.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.templateGeneration == generation else { return }
                self.stopTemplatePlayback()
                if self.isDemoMode {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        self.showPostDemoBanner = true
                    }
                }
            }
            return
        }

        let delay: TimeInterval = index == 0
            ? moves[0].timestamp
            : moves[index].timestamp - moves[index - 1].timestamp

        templateTimer = Timer.scheduledTimer(withTimeInterval: max(delay, 0.3), repeats: false) { [weak self] _ in
            guard let self, self.templateGeneration == generation else { return }
            DispatchQueue.main.async { [self] in
                guard self.templateGeneration == generation else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    self.templateMoveIndex = index
                }
                if UIApplication.shared.applicationState == .active {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                self.scheduleTemplateMove(at: index + 1, moves: moves, generation: generation)
            }
        }
    }

    func stopTemplatePlayback() {
        templateGeneration += 1
        templateTimer?.invalidate(); templateTimer = nil
        audioPlayer?.stop(); audioPlayer = nil
        isTemplatePlaybackActive = false
        templateMoveIndex = 0
        // 不在此处 deactivate AVAudioSession：
        // 模板可能在录制中自然结束（scheduleTemplateMove 触发），此时 deactivate 会中断麦克风。
        // session 由视图层在录制真正停止后统一调用 deactivateAudioSessionIfIdle() 管理。
    }

    /// 视图层在录制停止后调用——仅当两个播放器都已停止时才 deactivate session
    func deactivateAudioSessionIfIdle() {
        guard !(audioPlayer?.isPlaying ?? false),
              !(lipSyncAudioPlayer?.isPlaying ?? false) else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - 加载 Demo 模板（无需导入视频，直接体验）

    func loadDemoTemplate(_ entry: DemoEntry) {
        recordDanceUse()
        isDemoMode = true
        currentDemoEntry = entry
        importedTemplate = entry.template
        analysisErrorMessage = nil
        showPostDemoBanner = false
    }

    func clearTemplate() {
        stopTemplatePlayback()
        importedTemplate = nil
        isDemoMode = false
        currentDemoEntry = nil
        showPostDemoBanner = false
        analysisErrorMessage = nil
    }

    var currentTemplateMove: EmojiMove? {
        guard let t = importedTemplate, templateMoveIndex < t.emojiMoves.count else { return nil }
        return t.emojiMoves[templateMoveIndex]
    }
    var nextTemplateMove: EmojiMove? {
        guard let t = importedTemplate else { return nil }
        let next = templateMoveIndex + 1
        return next < t.emojiMoves.count ? t.emojiMoves[next] : nil
    }

    // MARK: - 对口型歌词滚动（使用 activeSong，支持自定义歌曲）

    private var analysisGeneration: Int = 0
    private var lyricStartDate: Date?

    func startLyricScroll() {
        stopLyricScroll()
        currentLyricIndex = 0
        simulatedPlaybackTime = 0
        lyricStartDate = Date()
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            // 在 dispatch 前捕获 startDate，防止 dispatch 后外部已重置 lyricStartDate
            guard let startDate = self.lyricStartDate else { return }
            let elapsed = Date().timeIntervalSince(startDate)
            self.simulatedPlaybackTime = elapsed
            let lines = self.activeSong.lines   // 自定义歌词优先
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
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
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
        templateTimer?.invalidate()
        audioPlayer?.stop()
        lipSyncAudioPlayer?.stop()
        cancellables.removeAll()
    }
}

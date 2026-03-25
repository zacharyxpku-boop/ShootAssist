import SwiftUI
import Vision
import AVFoundation
import Combine

class VideoModeViewModel: ObservableObject {
    @Published var currentSubMode: VideoSubMode = .videoTemplate
    @Published var selectedDelay: DelayOption = .three
    @Published var isCountingDown = false
    @Published var countdownValue = 3

    // MARK: - 对口型歌词
    @Published var selectedSong: SongLyrics = lyricDatabase[0]
    @Published var currentLyricIndex = 0
    @Published var showSongSelector = false
    @Published var simulatedPlaybackTime: TimeInterval = 0

    // MARK: - 跟拍手势舞（视频模版）
    @Published var showVideoPicker = false
    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0
    @Published var importedTemplate: AnalyzedTemplate? = nil
    @Published var templateMoveIndex: Int = 0
    @Published var isTemplatePlaybackActive = false
    @Published var analysisErrorMessage: String? = nil

    // MARK: - Demo 模板（免费体验）
    @Published var isDemoMode: Bool = false
    @Published var currentDemoEntry: DemoEntry? = nil
    @Published var showPostDemoBanner: Bool = false

    // MARK: - Vision 实时关键点（从 CameraViewModel 传入）
    @Published var liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    private var countdownTimer: Timer?
    private var lyricTimer: Timer?
    private var templateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var audioPlayer: AVAudioPlayer?
    private var templateGeneration: Int = 0

    // MARK: - 绑定 VisionService

    func bindVision(_ visionService: VisionService) {
        cancellables.removeAll()
        visionService.$bodyJoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in self?.liveJoints = joints }
            .store(in: &cancellables)
    }

    // MARK: - 导入视频并分析（含 90s 超时保护）

    func importAndAnalyzeVideo(asset: AVAsset) {
        isAnalyzing = true
        analysisProgress = 0
        importedTemplate = nil
        analysisErrorMessage = nil

        Task {
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 90_000_000_000)
                await MainActor.run {
                    guard self.isAnalyzing else { return }
                    self.isAnalyzing = false
                    self.analysisErrorMessage = "分析超时，请选择较短的视频（建议 60s 内）"
                }
            }

            let template = await VideoAnalysisService.shared.analyzeVideo(
                asset: asset,
                sampleInterval: 0.2
            ) { [weak self] progress in
                DispatchQueue.main.async { self?.analysisProgress = progress }
            }

            timeoutTask.cancel()

            await MainActor.run {
                guard self.isAnalyzing else { return }
                self.isAnalyzing = false
                if template.duration <= 0 {
                    self.analysisErrorMessage = "无法读取视频，请换一个视频文件"
                } else if template.emojiMoves.isEmpty {
                    self.importedTemplate = template
                    self.analysisErrorMessage = "未检测到明显手势，建议选人物清晰的舞蹈视频"
                } else {
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

        if let audioURL = template.audioURL,
           let player = try? AVAudioPlayer(contentsOf: audioURL) {
            audioPlayer = player
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        }

        scheduleTemplateMove(at: 0, moves: template.emojiMoves, generation: gen)
    }

    private func scheduleTemplateMove(at index: Int, moves: [EmojiMove], generation: Int) {
        guard index < moves.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.templateGeneration == generation else { return }
                self.stopTemplatePlayback()
                // Demo 完成后显示升级提示
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
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    self.templateMoveIndex = index
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
    }

    // MARK: - 加载 Demo 模板（无需导入视频，直接体验）

    func loadDemoTemplate(_ entry: DemoEntry) {
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

    // MARK: - 对口型歌词滚动

    func startLyricScroll() {
        stopLyricScroll(); currentLyricIndex = 0; simulatedPlaybackTime = 0
        lyricTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.simulatedPlaybackTime += 0.1
                let lines = self.selectedSong.lines
                let newIndex = lines.lastIndex(where: { $0.startTime <= self.simulatedPlaybackTime }) ?? 0
                if newIndex != self.currentLyricIndex {
                    withAnimation(.easeInOut(duration: 0.3)) { self.currentLyricIndex = newIndex }
                }
                if let last = lines.last, self.simulatedPlaybackTime > last.endTime + 1.0 {
                    self.simulatedPlaybackTime = 0; self.currentLyricIndex = 0
                }
            }
        }
    }

    func stopLyricScroll() { lyricTimer?.invalidate(); lyricTimer = nil; simulatedPlaybackTime = 0 }

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
        cancellables.removeAll()
    }
}

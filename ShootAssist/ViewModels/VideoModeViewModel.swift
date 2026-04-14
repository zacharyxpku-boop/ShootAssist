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
        isPiPPlaying = true
    }

    func clearReferenceVideo() {
        isPiPPlaying = false
        referenceVideoURL = nil
    }

    /// 录制开始时自动播放参考视频
    func startPiPPlayback() {
        if referenceVideoURL != nil { isPiPPlaying = true }
    }

    /// 录制停止时暂停参考视频
    func stopPiPPlayback() {
        isPiPPlaying = false
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
                    self.lyricRecognitionError = "视频音频提取失败，请换一个视频文件"
                }
            }
        }
    }

    /// 从视频中提取音频（原 VideoAnalysisService.extractAudio 移入此处）
    private static func extractAudio(from asset: AVAsset) async -> URL? {
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else { return nil }
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
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
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
        lipSyncAudioPlayer?.stop()
        cancellables.removeAll()
    }
}

import SwiftUI
import AVFoundation

struct VideoModeView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @StateObject private var cameraVM = CameraViewModel()
    @StateObject private var videoVM = VideoModeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var baseZoomLevel: CGFloat = 1.0
    @State private var showPaywall = false
    @State private var showDemoPicker = false
    @State private var showShareVideo = false
    @State private var shareVideoURL: URL? = nil
    @State private var isPreparingShare = false
    @State private var showAudioPicker = false
    @State private var showVideoPickerForLipSync = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white).frame(width: 44, height: 44)
                    }
                    Spacer()
                    Text("视频模式").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    // 前后摄切换（所有模式通用）
                    Button(action: { cameraVM.switchCamera() }) {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 17))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("切换摄像头")
                    .accessibilityValue(cameraVM.isFrontCamera ? "前置" : "后置")
                    // 右上角模式按钮
                    topRightButton
                }
                .padding(.horizontal, 8).background(Color.black)

                // 模式切换
                VideoSubModeTab(selected: $videoVM.currentSubMode)
                    .padding(.vertical, 8).background(Color.black)

                // 当前选择标签
                currentSelectionLabel
                    .padding(.horizontal, 16).padding(.bottom, 4).background(Color.black)

                // MARK: - 录像预览 + 辅助层
                ZStack {
                    CameraPreviewView(session: cameraVM.session, onTapToFocus: { point in
                        cameraVM.focusAt(point: point)
                    })
                        .gesture(MagnifyGesture()
                            .onChanged { value in
                                cameraVM.setZoom(baseZoomLevel * value.magnification)
                            }
                            .onEnded { _ in
                                baseZoomLevel = cameraVM.zoomLevel
                            }
                        )

                    GeometryReader { geo in
                        ZStack {
                            // 实时骨骼线（视频跟拍模式）
                            if videoVM.currentSubMode == .videoTemplate && !videoVM.liveJoints.isEmpty {
                                UpperBodySkeletonView(
                                    joints: videoVM.liveJoints,
                                    viewSize: geo.size,
                                    lineColor: Color(hex: "FFCBA4"),
                                    lineWidth: 2
                                )
                            }

                            // REC 指示器
                            if cameraVM.isRecording {
                                Text(cameraVM.formattedDuration)
                                    .font(.system(size: 14, weight: .light)).tracking(2)
                                    .foregroundColor(.white)
                                    .position(x: geo.size.width / 2, y: 30)

                                HStack(spacing: 4) {
                                    RecDot()
                                    Text("REC").font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                .position(x: geo.size.width - 50, y: 20)
                            }

                            // 对口型歌词
                            if videoVM.currentSubMode == .lipSync {
                                LyricsView(
                                    lines: videoVM.activeSong.lines,
                                    currentIndex: videoVM.currentLyricIndex,
                                    playbackTime: videoVM.simulatedPlaybackTime
                                )
                                .position(x: geo.size.width / 2, y: geo.size.height * 0.82)
                            }

                            // 视频跟拍 emoji 引导
                            if videoVM.currentSubMode == .videoTemplate {
                                VideoTemplateOverlay(
                                    viewModel: videoVM,
                                    viewSize: geo.size
                                )
                            }
                        }
                    }

                    // 倒计时
                    if videoVM.isCountingDown { CountdownOverlay(value: videoVM.countdownValue) }

                    // 分析进度遮罩
                    if videoVM.isAnalyzing {
                        AnalyzingOverlay(progress: videoVM.analysisProgress)
                    }

                    // 视频音频提取中遮罩
                    if videoVM.isExtractingVideoAudio {
                        VideoExtractAudioOverlay()
                    }

                    // 歌词识别中遮罩
                    if videoVM.isRecognizingLyrics {
                        LyricRecognizingOverlay(name: videoVM.customMusicName)
                    }

                    // 低光提示
                    if cameraVM.visionService.isLowLightWarning
                        && videoVM.currentSubMode == .videoTemplate
                        && !cameraVM.isRecording {
                        VStack {
                            Spacer()
                            HStack(spacing: 8) {
                                Image(systemName: "sun.min").font(.system(size: 13)).foregroundColor(.honeyOrange)
                                Text("检测不到人物，试试光线更亮的地方")
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                            .padding(.bottom, 20)
                        }
                        .transition(.opacity)
                    }

                    // 视频录制完成后的分享横幅
                    if isPreparingShare {
                        VideoSaveProgressBanner()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Demo 完成后的升级横幅
                    if videoVM.showPostDemoBanner {
                        PostDemoBanner(onUpgrade: {
                            videoVM.showPostDemoBanner = false
                            showPaywall = true
                        }, onDismiss: {
                            withAnimation { videoVM.showPostDemoBanner = false }
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 2)

                // MARK: - 底部操作栏
                HStack {
                    Button(action: { handleLeftButton() }) {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 34, height: 34)
                            .overlay(Image(systemName: leftButtonIcon).foregroundColor(.white).font(.system(size: 14)))
                    }
                    Spacer()
                    RecordButton(isRecording: cameraVM.isRecording) {
                        if cameraVM.isRecording {
                            cameraVM.stopRecording()
                            videoVM.stopTemplatePlayback()
                            videoVM.deactivateAudioSessionIfIdle()  // BUG1 fix：录制真正停止后才释放 session
                            if videoVM.currentSubMode == .lipSync {
                                videoVM.stopLipSyncAudio()  // 内部已调用 deactivateAudioSessionIfIdle
                                videoVM.stopLyricScroll()
                                videoVM.startLyricScroll()  // 恢复预览
                            }
                        } else if videoVM.isCountingDown {
                            videoVM.cancelCountdown()       // BUG3 fix：倒计时中按钮取消倒计时
                        } else {
                            videoVM.startCountdown {
                                cameraVM.startRecording()
                                if videoVM.currentSubMode == .videoTemplate {
                                    videoVM.startTemplatePlayback()
                                } else if videoVM.currentSubMode == .lipSync {
                                    // 从头同步：先重启歌词滚动，再播放音频
                                    videoVM.stopLyricScroll()
                                    videoVM.startLyricScroll()
                                    if videoVM.customMusicURL != nil {
                                        videoVM.startLipSyncAudio()
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    Button(action: { videoVM.cycleDelay() }) {
                        Text(videoVM.selectedDelay.label)
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                    }
                }
                .padding(.horizontal, 30).padding(.vertical, 16).background(Color.black)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toast(isShowing: $cameraVM.showToast)
        .errorToast(isShowing: $cameraVM.showSaveError, message: cameraVM.saveErrorMessage)
        .onAppear {
            cameraVM.isVideoMode = true
            cameraVM.enableVisionAnalysis = needsVision
            cameraVM.checkPermission()
            videoVM.bindVision(cameraVM.visionService)
            handleSubModeChange()
        }
        .onDisappear {
            videoVM.cancelCountdown()
            videoVM.stopLyricScroll()
            videoVM.stopTemplatePlayback()
            videoVM.stopLipSyncAudio()
            cameraVM.stopSession()
        }
        .onChange(of: videoVM.currentSubMode) { newMode in
            guard !cameraVM.isRecording else { return }  // BUG2 fix：录制中禁止切换模式，防止破坏 session
            cameraVM.enableVisionAnalysis = (newMode == .videoTemplate)
            handleSubModeChange()
        }
        .overlay { if cameraVM.permissionDenied { PermissionDeniedOverlay() } }
        .sheet(isPresented: $videoVM.showSongSelector) {
            SongSelectorSheet(
                videoVM: videoVM,
                isPresented: $videoVM.showSongSelector,
                showAudioPicker: $showAudioPicker,
                showVideoPickerForLipSync: $showVideoPickerForLipSync
            )
            .onDisappear {
                videoVM.stopLyricScroll()
                videoVM.startLyricScroll()
            }
        }
        .sheet(isPresented: $showAudioPicker) {
            AudioPickerView { url in
                showAudioPicker = false
                guard let url else { return }
                videoVM.importCustomAudio(url: url)
            }
        }
        .sheet(isPresented: $showVideoPickerForLipSync) {
            VideoPicker { asset in
                showVideoPickerForLipSync = false
                guard let asset else { return }
                videoVM.importVideoForLipSync(asset: asset)
            }
        }
        // 录制完成 → 加水印 → 显示分享横幅
        .onChange(of: cameraVM.lastSavedVideoURL) { url in
            guard let url else { return }
            showShareVideo = false; isPreparingShare = true
            VideoWatermarkService.shared.addWatermark(to: url) { watermarked in
                self.shareVideoURL = watermarked ?? url
                self.isPreparingShare = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    self.showShareVideo = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    withAnimation { self.showShareVideo = false }
                }
            }
        }
        .sheet(isPresented: $showShareVideo) {
            if let url = shareVideoURL {
                ShareSheet(
                    items: [url, ReferralManager.shareAppendText()],
                    onDismiss: { showShareVideo = false },
                    onComplete: {
                        ReferralManager.recordShareAction()
                        Analytics.track(Analytics.Event.videoShared)
                        Analytics.track(Analytics.Event.referralGenerated)
                    }
                )
            }
        }
        .sheet(isPresented: $videoVM.showVideoPicker) {
            VideoPicker { asset in
                guard let asset else { return }
                videoVM.importAndAnalyzeVideo(asset: asset)
            }
        }
        .sheet(isPresented: $showDemoPicker) {
            DemoPickerSheet(videoVM: videoVM, isPresented: $showDemoPicker, showPaywall: $showPaywall)
                .environmentObject(subManager)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
    }

    // MARK: - 计算属性

    private var needsVision: Bool {
        videoVM.currentSubMode == .videoTemplate
    }

    @ViewBuilder
    private var topRightButton: some View {
        switch videoVM.currentSubMode {
        case .lipSync:
            Button(action: { videoVM.showSongSelector = true }) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 18)).foregroundColor(.white).frame(width: 44, height: 44)
            }
            .disabled(cameraVM.isRecording)
        case .videoTemplate:
            // 免费用户每日10次，达上限才引导 Pro；分析中禁止重复导入
            Button(action: {
                if videoVM.isDanceLimitReached(isPro: subManager.isPro) {
                    showPaywall = true
                } else {
                    videoVM.showVideoPicker = true
                }
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "video.badge.plus")
                        .font(.system(size: 18)).foregroundColor(videoVM.isAnalyzing ? .white.opacity(0.3) : .white)
                    if videoVM.isDanceLimitReached(isPro: subManager.isPro) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.honeyOrange)
                            .offset(x: 6, y: -6)
                    }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(videoVM.isAnalyzing)
        }
    }

    @ViewBuilder
    private var currentSelectionLabel: some View {
        HStack {
            switch videoVM.currentSubMode {
            case .lipSync:
                if videoVM.isRecognizingLyrics {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7).tint(.white)
                        Text("正在识别「\(videoVM.customMusicName)」的歌词…")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.7))
                    }
                } else if let custom = videoVM.customSongLyrics {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note").font(.system(size: 10)).foregroundColor(.rosePink)
                        Text("\(custom.songName) · 自定义")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                        if let err = videoVM.lyricRecognitionError {
                            Text("·").foregroundColor(.white.opacity(0.3)).font(.system(size: 10))
                            Text(err).font(.system(size: 9)).foregroundColor(.honeyOrange)
                        }
                    }
                } else {
                    Text("🎵 \(videoVM.selectedSong.songName) - \(videoVM.selectedSong.artist)")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                }
            case .videoTemplate:
                if videoVM.isAnalyzing {
                    Text("⏳ 分析中… \(Int(videoVM.analysisProgress * 100))%")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                } else if let err = videoVM.analysisErrorMessage {
                    Text("⚠️ \(err)")
                        .font(.system(size: 10)).foregroundColor(.orange.opacity(0.9))
                } else if let t = videoVM.importedTemplate {
                    if videoVM.isDemoMode, let demo = videoVM.currentDemoEntry {
                        HStack(spacing: 6) {
                            Text("\(demo.icon) Demo · \(demo.name) · \(t.emojiMoves.count) 个手势")
                                .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Button(action: { showDemoPicker = true }) {
                                Text("换一个").font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.honeyOrange).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.honeyOrange.opacity(0.15)))
                            }
                        }
                    } else {
                        Text("✅ 已提取 \(t.emojiMoves.count) 个手势 · \(String(format: "%.0f", t.duration))s")
                            .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    HStack(spacing: 8) {
                        Button(action: { showDemoPicker = true }) {
                            HStack(spacing: 4) {
                                Text("✨").font(.system(size: 11))
                                Text("先试试内置 Demo").font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing)))
                        }
                        if !subManager.isPro {
                            Text("今日剩余 \(videoVM.freeDanceRemaining) 次")
                                .font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                        } else {
                            Text("或点右上角导入视频").font(.system(size: 9)).foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private var leftButtonIcon: String {
        switch videoVM.currentSubMode {
        case .lipSync: return "music.note.list"
        case .videoTemplate: return "sparkles"
        }
    }

    private func handleLeftButton() {
        switch videoVM.currentSubMode {
        case .lipSync: videoVM.showSongSelector = true
        case .videoTemplate: showDemoPicker = true
        }
    }

    private func handleSubModeChange() {
        videoVM.stopLyricScroll()
        videoVM.stopTemplatePlayback()
        switch videoVM.currentSubMode {
        case .lipSync: videoVM.startLyricScroll()
        case .videoTemplate: break
        }
    }
}

// MARK: - 视频跟拍 emoji 引导层

private struct VideoTemplateOverlay: View {
    @ObservedObject var viewModel: VideoModeViewModel
    let viewSize: CGSize

    var body: some View {
        ZStack {
            // 空闲状态（未导入 / 未开始录制）保持在底部，不遮挡拍摄区域
            if viewModel.currentTemplateMove == nil {
                VStack(spacing: 6) {
                    if viewModel.importedTemplate == nil {
                        Image(systemName: "video.badge.plus")
                            .font(.system(size: 32)).foregroundColor(.white.opacity(0.4))
                        Text("导入一段舞蹈视频").font(.system(size: 13)).foregroundColor(.white.opacity(0.4))
                        Text("自动提取手势做引导").font(.system(size: 11)).foregroundColor(.white.opacity(0.3))
                    } else if !viewModel.isTemplatePlaybackActive {
                        Image(systemName: "play.circle")
                            .font(.system(size: 32)).foregroundColor(.white.opacity(0.4))
                        Text("按下录制按钮开始跟拍").font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                    }
                }
                .position(x: viewSize.width / 2, y: viewSize.height * 0.82)
            }

            // 跟拍进行中：emoji 定位在画面上方 1/3 处，透明度 75%
            // 拍摄者视线平视摄像头时正好能看到动作提示，不遮主体
            if let move = viewModel.currentTemplateMove {
                VStack(spacing: 4) {
                    Text(move.emoji)
                        .font(.system(size: 60))
                        .shadow(color: .black.opacity(0.3), radius: 4)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 1.3).combined(with: .opacity),
                            removal: .scale(scale: 0.7).combined(with: .opacity)
                        ))
                        .id("emoji_\(move.id)")

                    Text(move.description)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 3)

                    if let next = viewModel.nextTemplateMove {
                        HStack(spacing: 4) {
                            Text("下一个").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            Text(next.emoji).font(.system(size: 18))
                            Text(next.description).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top, 2)
                    }
                }
                .opacity(0.75)
                .position(x: viewSize.width / 2, y: viewSize.height * 0.18)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.templateMoveIndex)
            }
        }
    }
}

// MARK: - 视频音频提取中遮罩

private struct VideoExtractAudioOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .honeyOrange))
                    .scaleEffect(1.4)
                Text("正在提取视频音频").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text("稍等一下，马上识别歌词…")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 歌词识别中遮罩

private struct LyricRecognizingOverlay: View {
    let name: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .rosePink))
                    .scaleEffect(1.4)
                Text("正在识别歌词").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                Text(name.isEmpty ? "分析音频中…" : "「\(name)」")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 分析中遮罩

private struct AnalyzingOverlay: View {
    let progress: Double
    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 4).frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(
                            LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.2), value: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                }
                Text("正在分析视频手势…").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                Text("AI 正在识别每一帧的动作").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
            }
        }
    }
}

// MARK: - 子组件

private struct VideoSubModeTab: View {
    @Binding var selected: VideoSubMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(VideoSubMode.allCases) { mode in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) { selected = mode }
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: selected == mode ? .semibold : .regular))
                        .foregroundColor(selected == mode ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Group {
                            if selected == mode {
                                Capsule().fill(LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing))
                                    .shadow(color: .rosePink.opacity(0.3), radius: 4, y: 2)
                            }
                        })
                }
            }
        }
        .padding(3).background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

private struct RecordButton: View {
    let isRecording: Bool; let action: () -> Void
    @State private var isPressed = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.white).frame(width: 56, height: 56).shadow(color: .red.opacity(0.25), radius: 12)
                if isRecording { RoundedRectangle(cornerRadius: 6).fill(Color.red).frame(width: 24, height: 24) }
                else { Circle().fill(Color.red).frame(width: 48, height: 48) }
            }
            .scaleEffect(isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        }
        .accessibilityLabel(isRecording ? "停止录像" : "开始录像")
        .accessibilityAddTraits(.isButton)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in isPressed = true }.onEnded { _ in isPressed = false })
    }
}

private struct RecDot: View {
    @State private var vis = true
    var body: some View {
        Circle().fill(Color.red).frame(width: 6, height: 6).opacity(vis ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { vis = false } }
    }
}

private struct CountdownOverlay: View {
    let value: Int; @State private var scale: CGFloat = 1.1
    var body: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea().overlay(.ultraThinMaterial.opacity(0.3))
            Text("\(value)").font(.system(size: 80, weight: .black))
                .foregroundStyle(LinearGradient(colors: [.rosePink, .honeyOrange], startPoint: .top, endPoint: .bottom))
                .scaleEffect(scale)
                .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { scale = 0.9 } }
                .onChange(of: value) { _ in
                    scale = 1.1
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { scale = 0.9 }
                }
        }
    }
}

private struct PermissionDeniedOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.fill").font(.system(size: 40)).foregroundColor(.rosePink)
            Text("需要相机和麦克风权限").font(.system(size: 18, weight: .semibold)).foregroundColor(.berryBrown)
            Text("请在「设置」中开启相关权限").font(.system(size: 13)).foregroundColor(.midBerryBrown)
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }) {
                Text("前往设置").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(LinearGradient(colors: [.rosePink, .deepRose], startPoint: .leading, endPoint: .trailing)))
            }
        }
        .padding(40).background(RoundedRectangle(cornerRadius: 24).fill(.white).shadow(color: .rosePink.opacity(0.15), radius: 20, y: 8))
    }
}

// MARK: - 歌曲选择器（含自定义音乐上传）

private struct SongSelectorSheet: View {
    @ObservedObject var videoVM: VideoModeViewModel
    @Binding var isPresented: Bool
    @Binding var showAudioPicker: Bool
    @Binding var showVideoPickerForLipSync: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 上传自定义音乐（音频文件）
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showAudioPicker = true
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.rosePink)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("上传自己的音乐")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.berryBrown)
                            Text(videoVM.customMusicURL != nil
                                 ? "已上传：\(videoVM.customMusicName)"
                                 : "从「文件」App 选择 MP3/M4A/WAV")
                                .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                        }
                        Spacer()
                        if videoVM.isRecognizingLyrics {
                            ProgressView().scaleEffect(0.8)
                        } else if videoVM.customSongLyrics != nil {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14)).foregroundColor(.midBerryBrown.opacity(0.5))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.rosePink.opacity(0.07)))
                }
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)

                // 从本地视频提取音乐
                Button(action: {
                    isPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showVideoPickerForLipSync = true
                    }
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "video.circle.fill")
                            .font(.system(size: 28)).foregroundColor(.honeyOrange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("从视频提取音乐")
                                .font(.system(size: 15, weight: .semibold)).foregroundColor(.berryBrown)
                            Text("自动提取视频音频 · 自动识别歌词")
                                .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                        }
                        Spacer()
                        if videoVM.isExtractingVideoAudio {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14)).foregroundColor(.midBerryBrown.opacity(0.5))
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.honeyOrange.opacity(0.07)))
                }
                .padding(.horizontal, 16).padding(.bottom, 4)

                // 识别错误提示
                if let err = videoVM.lyricRecognitionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundColor(.honeyOrange)
                        Text(err).font(.system(size: 11)).foregroundColor(.honeyOrange)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 6)
                }

                // 清除自定义音乐
                if videoVM.customMusicURL != nil && !videoVM.isRecognizingLyrics {
                    Button(action: { videoVM.clearCustomMusic() }) {
                        Text("移除自定义音乐，恢复内置歌曲")
                            .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                    }
                    .padding(.bottom, 8)
                }

                Divider().padding(.horizontal, 16)

                Text("内置歌曲")
                    .font(.system(size: 11, weight: .medium)).foregroundColor(.midBerryBrown)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)

                List(lyricDatabase) { song in
                    Button(action: {
                        videoVM.selectedSong = song
                        videoVM.clearCustomMusic()
                        isPresented = false
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.songName)
                                    .font(.system(size: 15, weight: .medium)).foregroundColor(.berryBrown)
                                Text(song.artist)
                                    .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                            }
                            Spacer()
                            if song.id == videoVM.selectedSong.id && videoVM.customSongLyrics == nil {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.rosePink)
                            }
                        }
                    }
                    .listRowBackground(Color(hex: "FAFAF9"))
                }
                .listStyle(.plain)
            }
            .background(Color(hex: "FAFAF9").ignoresSafeArea())
            .navigationTitle("选择歌曲").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { isPresented = false } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 视频处理中提示

private struct VideoSaveProgressBanner: View {
    @State private var dots = ""
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 12) {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.85)
                Text("正在添加水印\(dots)").font(.system(size: 13, weight: .medium)).foregroundColor(.white)
                Spacer()
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.7)))
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .onReceive(timer) { _ in dots = dots.count < 3 ? dots + "." : "" }
    }
}

// MARK: - Demo 模板选择器

private struct DemoPickerSheet: View {
    @ObservedObject var videoVM: VideoModeViewModel
    @EnvironmentObject var subManager: SubscriptionManager
    @Binding var isPresented: Bool
    @Binding var showPaywall: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("选一个 Demo 先感受一下")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.berryBrown)
                    if !subManager.isPro {
                        Text("今日剩余免费次数：\(videoVM.freeDanceRemaining)/\(VideoModeViewModel.freeDanceLimitPerDay)")
                            .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                    } else {
                        Text("跟着 emoji 做动作就行，不用导入视频")
                            .font(.system(size: 12)).foregroundColor(.midBerryBrown)
                    }
                }
                .padding(.top, 8).padding(.bottom, 20)

                VStack(spacing: 12) {
                    ForEach(demoTemplates) { entry in
                        Button(action: {
                            if videoVM.isDanceLimitReached(isPro: subManager.isPro) {
                                isPresented = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    showPaywall = true
                                }
                            } else {
                                videoVM.loadDemoTemplate(entry); isPresented = false
                            }
                        }) {
                            HStack(spacing: 16) {
                                Text(entry.icon).font(.system(size: 36))
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(Color.rosePink.opacity(0.1)))

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(entry.name).font(.system(size: 16, weight: .semibold)).foregroundColor(.berryBrown)
                                        Text(entry.durationLabel).font(.system(size: 11)).foregroundColor(.midBerryBrown)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(Color.midBerryBrown.opacity(0.12)))
                                    }
                                    Text(entry.description).font(.system(size: 12)).foregroundColor(.midBerryBrown)
                                    HStack(spacing: 2) {
                                        ForEach(entry.template.emojiMoves.prefix(6)) { move in
                                            Text(move.emoji).font(.system(size: 14))
                                        }
                                        if entry.template.emojiMoves.count > 6 {
                                            Text("…").font(.system(size: 12)).foregroundColor(.midBerryBrown)
                                        }
                                    }
                                }
                                Spacer()
                                if videoVM.isDemoMode && videoVM.currentDemoEntry?.name == entry.name {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.rosePink).font(.system(size: 20))
                                } else {
                                    Image(systemName: "chevron.right").foregroundColor(.midBerryBrown.opacity(0.4)).font(.system(size: 14))
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(videoVM.isDemoMode && videoVM.currentDemoEntry?.name == entry.name
                                          ? Color.rosePink.opacity(0.06) : Color.white)
                                    .shadow(color: Color.berryBrown.opacity(0.06), radius: 8, y: 2)
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .background(Color(hex: "FAFAF9").ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { isPresented = false } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Demo 完成后升级横幅

private struct PostDemoBanner: View {
    let onUpgrade: () -> Void
    let onDismiss: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("🎉").font(.system(size: 20))
                    Text("感觉还不错？").font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.5))
                    }
                }
                Text("导入你自己喜欢的舞蹈视频\nAI 自动变成你的专属跟拍引导")
                    .font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onUpgrade) {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill").font(.system(size: 12))
                        Text("解锁 Pro · 导入任意视频").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.berryBrown)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.white))
                    .scaleEffect(pulse ? 1.02 : 1.0)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                }
                .onAppear { pulse = true }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [Color(hex: "E8547A"), Color(hex: "F2976A")],
                                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.25), radius: 16, y: -4)
            )
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
    }
}

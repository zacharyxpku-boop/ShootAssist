import SwiftUI
import AVFoundation

struct VideoModeView: View {
    @StateObject private var cameraVM = CameraViewModel()
    @StateObject private var videoVM = VideoModeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var baseZoomLevel: CGFloat = 1.0
    @State private var showShareSheet: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航（精简内嵌式，命中区扩到 HIG 44×44）
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("返回")
                    Spacer()

                    // 导入参考视频
                    Button(action: { videoVM.showVideoPicker = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: videoVM.referenceVideoURL != nil ? "film.fill" : "film")
                                .font(.system(size: 13))
                            Text(videoVM.referenceVideoURL != nil ? "换视频" : "导入参考")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .frame(minHeight: 44)
                    }
                    .accessibilityLabel(videoVM.referenceVideoURL != nil ? "更换参考视频" : "导入参考视频")

                    // 前后摄切换
                    Button(action: { cameraVM.switchCamera() }) {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("切换摄像头")

                    // 闪光灯
                    Button(action: { cameraVM.toggleFlash() }) {
                        Image(systemName: cameraVM.flashIcon)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("闪光灯")
                }
                .padding(.horizontal, 12).padding(.vertical, 2)

                // MARK: - 相机预览 + PiP
                ZStack {
                    // 16:9 全屏相机预览
                    CameraPreviewView(session: cameraVM.session, onTapToFocus: { point in
                        cameraVM.focusAt(point: point)
                    })
                    .gesture(MagnificationGesture()
                        .onChanged { scale in
                            cameraVM.setZoom(baseZoomLevel * scale)
                        }
                        .onEnded { _ in
                            baseZoomLevel = cameraVM.zoomLevel
                        }
                    )

                    GeometryReader { geo in
                        ZStack {
                            // 画中画参考视频
                            if let url = videoVM.referenceVideoURL {
                                DraggablePiPView(
                                    url: url,
                                    screenSize: geo.size,
                                    isPlaying: $videoVM.isPiPPlaying,
                                    restartToken: videoVM.pipRestartToken,
                                    audioEnabled: videoVM.pipAudioEnabled
                                )
                                .position(
                                    x: geo.size.width / 6 + 8,
                                    y: geo.size.width / 6 * 16 / 9 / 2 + 8
                                )
                            }

                            // REC 指示器
                            if cameraVM.isRecording {
                                HStack(spacing: 4) {
                                    RecDot()
                                    Text(cameraVM.formattedDuration)
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                .position(x: geo.size.width / 2, y: 20)
                            }

                            // 清除参考视频按钮
                            if videoVM.referenceVideoURL != nil && !cameraVM.isRecording {
                                Button(action: { videoVM.clearReferenceVideo() }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                .position(x: geo.size.width - 24, y: 24)
                            }
                        }
                    }

                    // 倒计时
                    if videoVM.isCountingDown {
                        CountdownOverlay(value: videoVM.countdownValue)
                    }
                }
                // 放弃 aspectRatio 约束，让 ZStack 填满 VStack 剩余空间
                // CameraPreviewView 内部用 .resizeAspectFill 保持比例 + 铺满（和系统相机 Reels 一致）
                // 之前 aspectRatio 约束在嵌套 VStack 里会导致 SwiftUI 分配异常 frame，预览被拉伸
                .clipped()

                // MARK: - 底部操作栏（精简）
                HStack {
                    // 延时
                    Button(action: { videoVM.cycleDelay() }) {
                        Text(videoVM.selectedDelay.label)
                            .font(.system(size: 11, weight: .medium)).foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("延时拍摄")
                    .accessibilityValue(videoVM.selectedDelay.label)
                    Spacer()

                    // 录制按钮
                    RecordButton(isRecording: cameraVM.isRecording) {
                        if cameraVM.isRecording {
                            cameraVM.stopRecording()
                            videoVM.stopPiPPlayback()
                            videoVM.deactivateAudioSessionIfIdle()
                        } else if videoVM.isCountingDown {
                            videoVM.cancelCountdown()
                        } else {
                            // 倒计时开始时暂停 PiP 预览
                            // 不在这里调 startPiPPlaybackSynced — startRecording 是异步的
                            // 真正开录的瞬间由 onChange(recordingStartToken) 触发 PiP 同步
                            videoVM.stopPiPPlayback()
                            videoVM.startCountdown {
                                cameraVM.startRecording()
                            }
                        }
                    }

                    Spacer()

                    // 分享最近一条（录制结束且已保存后出现）
                    if cameraVM.lastCapturedVideoURL != nil {
                        Button(action: {
                            Analytics.track(Analytics.Event.videoShared)
                            showShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14)).foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(Color.white.opacity(0.18)))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("分享最近一条")
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }

                    // 前后摄（底部备用入口）
                    Button(action: { cameraVM.switchCamera() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13)).foregroundColor(.white)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.12)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("切换摄像头")
                }
                .padding(.horizontal, 40).padding(.vertical, 12)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toast(isShowing: $cameraVM.showToast)
        .errorToast(isShowing: $cameraVM.showSaveError, message: cameraVM.saveErrorMessage)
        .onAppear {
            cameraVM.isVideoMode = true
            cameraVM.enableVisionAnalysis = false  // PiP 模式不需要 Vision
            cameraVM.checkPermission()
        }
        .onDisappear {
            videoVM.cancelCountdown()
            videoVM.stopPiPPlayback()
            cameraVM.stopSession()
        }
        .overlay { if cameraVM.permissionDenied { PermissionDeniedOverlay() } }
        .sheet(isPresented: $videoVM.showVideoPicker) {
            VideoPicker { asset in
                videoVM.showVideoPicker = false
                guard let asset else { return }
                if let urlAsset = asset as? AVURLAsset {
                    videoVM.importReferenceVideo(url: urlAsset.url)
                } else {
                    Task {
                        if let url = await Self.exportAssetToTemp(asset) {
                            await MainActor.run { videoVM.importReferenceVideo(url: url) }
                        }
                    }
                }
            }
        }
        // movieOutput 真正开始写文件的瞬间才同步 PiP — 消除 startRecording() 异步派发引起的时差
        .onChange(of: cameraVM.recordingStartToken) { _ in
            videoVM.startPiPPlaybackSynced()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = cameraVM.lastCapturedVideoURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 辅助

    @MainActor
    private static func exportAssetToTemp(_ asset: AVAsset) async -> URL? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_ref_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outputURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { return nil }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        return session.status == .completed ? outputURL : nil
    }
}

// MARK: - 录制按钮
private struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 56, height: 56)
                if isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.red)
                        .frame(width: 22, height: 22)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 46, height: 46)
                }
            }
        }
    }
}

// MARK: - REC 闪烁点
private struct RecDot: View {
    @State private var visible = true
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible.toggle() }
            }
    }
}

// MARK: - 倒计时
private struct CountdownOverlay: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(.system(size: 72, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.5), radius: 10)
            .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - 权限拒绝
private struct PermissionDeniedOverlay: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.gray)
            Text("需要相机权限").font(.system(size: 16, weight: .medium)).foregroundColor(.white)
            Text("请在设置中允许小白快门访问相机")
                .font(.system(size: 13)).foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("打开设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(Capsule().fill(Color.rosePink))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}

import SwiftUI
import AVFoundation
import Photos

class CameraViewModel: NSObject, ObservableObject {
    @Published var isSessionRunning = false
    @Published var isFrontCamera = false
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var showToast = false
    @Published var showFlash = false
    @Published var permissionDenied = false
    @Published var showSaveError = false
    @Published var saveErrorMessage = ""
    @Published var sessionPhotosSaved = 0
    @Published var totalPhotosSaved: Int = UserDefaults.standard.integer(forKey: "totalPhotosSaved")
    @Published var lastSavedImage: UIImage? = nil
    @Published var lastSavedVideoURL: URL? = nil
    @Published var zoomLevel: CGFloat = 1.0
    @Published var isFocusing = false
    /// 当前摄像头实际宽高比（portrait，width/height），SwiftUI 用此值约束预览容器
    /// 防止前后摄像头 activeFormat 不同导致的画面拉伸变形
    @Published var previewAspectRatio: CGFloat = 3.0 / 4.0
    /// movieOutput 真正开始写文件的瞬间递增 — View 层监听此 token 触发 PiP seek(0)+play
    /// 修复"PiP 提前播"：cameraVM.startRecording() 是异步派发，返回后文件还没开始写
    @Published var recordingStartToken: Int = 0

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var currentDevice: AVCaptureDevice?
    private let sessionQueue = DispatchQueue(label: "com.shootassist.camera")
    private let visionQueue  = DispatchQueue(label: "com.shootassist.vision", qos: .userInitiated)

    let visionService = VisionService()

    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    private var recordingTimer: Timer?
    private var tempVideoURL: URL?

    var isVideoMode = false
    private var isCapturingPhoto = false
    /// Vision 分析开关：output 始终挂载，通过此 flag 在 delegate 中过滤
    var enableVisionAnalysis = true
    private var isConfigured = false
    private var focusResetWorkItem: DispatchWorkItem?

    /// 设置 connection 为竖屏方向（兼容 iOS 16 和 iOS 17+）
    private func setPortraitOrientation(_ conn: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
        } else {
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        }
    }

    /// 根据 sessionPreset 返回 portrait 宽高比 (短边/长边)
    /// 关键：activeFormat 给的是 sensor native 格式，不是 session 实际输出；
    /// 实际输出取决于 sessionPreset，所以按 preset 推导才准。
    private func updatePreviewAspectRatio() {
        let ratio: CGFloat
        switch session.sessionPreset {
        case .photo:
            ratio = 3.0 / 4.0   // .photo = 4:3 landscape → 3:4 portrait
        case .hd1920x1080, .hd1280x720, .hd4K3840x2160, .iFrame1280x720, .iFrame960x540:
            ratio = 9.0 / 16.0  // 16:9 landscape → 9:16 portrait
        case .vga640x480, .cif352x288:
            ratio = 3.0 / 4.0   // 4:3 legacy
        case .high, .medium, .low:
            // .high/.medium/.low 不确定，fallback 到 activeFormat 读
            if let device = currentDevice {
                let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                let w = CGFloat(min(dims.width, dims.height))
                let h = CGFloat(max(dims.width, dims.height))
                ratio = h > 0 ? w / h : 3.0 / 4.0
            } else {
                ratio = 3.0 / 4.0
            }
        default:
            ratio = 3.0 / 4.0
        }
        DispatchQueue.main.async { [weak self] in
            self?.previewAspectRatio = ratio
        }
    }

    override init() { super.init() }

    deinit { recordingTimer?.invalidate() }

    // MARK: - 权限

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            requestAudioThenSetup()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.requestAudioThenSetup() }
                else { DispatchQueue.main.async { self?.permissionDenied = true } }
            }
        default:
            DispatchQueue.main.async { [weak self] in self?.permissionDenied = true }
        }
    }

    private func requestAudioThenSetup() {
        if isVideoMode {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in self?.setupSession() }
            default:
                setupSession()
            }
        } else {
            setupSession()
        }
    }

    // MARK: - 配置会话

    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if self.session.isRunning {
                DispatchQueue.main.async { self.isSessionRunning = true }
                return
            }

            self.session.beginConfiguration()

            // 清除旧 inputs / outputs，再重建，避免 "already attached" 错误
            for input  in self.session.inputs  { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }

            // 视频输入（preset 必须在 input 加入后才能准确判断 canSet）
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input  = try? AVCaptureDeviceInput(device: camera) else {
                self.session.commitConfiguration(); return
            }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentDevice = camera
            }

            // 视频模式优先用 1080p 固定 preset，防止 .high 在不同设备上回退到 720p 甚至更低
            // 关键：必须在 addInput 之后调用 canSetSessionPreset，否则返回不准确
            if self.isVideoMode {
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                } else if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                } else {
                    self.session.sessionPreset = .high
                }
            } else {
                if self.session.canSetSessionPreset(.photo) { self.session.sessionPreset = .photo }
            }

            // 麦克风（视频模式）
            if self.isVideoMode,
               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let mic       = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }

            // 重建 outputs
            self.photoOutput    = AVCapturePhotoOutput()
            self.movieOutput    = AVCaptureMovieFileOutput()
            self.videoDataOutput = AVCaptureVideoDataOutput()

            if self.session.canAddOutput(self.photoOutput)  { self.session.addOutput(self.photoOutput) }
            if self.session.canAddOutput(self.movieOutput)  { self.session.addOutput(self.movieOutput) }

            // Vision 帧分析（始终挂载，通过 enableVisionAnalysis 开关控制）
            self.videoDataOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
            self.videoDataOutput.alwaysDiscardsLateVideoFrames = true
            self.videoDataOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if self.session.canAddOutput(self.videoDataOutput) {
                self.session.addOutput(self.videoDataOutput)
            }

            // videoOrientation 确保 sampleBuffer 以竖屏方向传给 Vision（默认可能是横向传感器朝向）
            if let conn = self.videoDataOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
            }
            // movieOutput connection 同步设置竖屏方向，防止初始录制方向错乱
            if let conn = self.movieOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
            }
            // ✅ photoOutput 补设 videoOrientation，避免拍出的照片方向元数据错误
            if let conn = self.photoOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                // 初始后置摄像头不镜像；切换前置后由 switchCamera 更新
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
            }

            self.session.commitConfiguration()
            self.session.startRunning()
            self.isConfigured = true

            // 计算并发布实际宽高比（关键：防前后摄 activeFormat 不同导致拉伸）
            self.updatePreviewAspectRatio()

            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.isFrontCamera = false
            }
        }
    }

    // MARK: - 切换摄像头

    func switchCamera() {
        guard !isRecording else { return }  // 录制中禁止切换，防止 session 配置崩溃
        let currentlyFront = isFrontCamera  // 主线程捕获，避免后台线程读脏值
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()

            for input in self.session.inputs {
                if let deviceInput = input as? AVCaptureDeviceInput,
                   deviceInput.device.hasMediaType(.video) {
                    self.session.removeInput(deviceInput)
                    break
                }
            }

            let newPosition: AVCaptureDevice.Position = currentlyFront ? .back : .front
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput  = try? AVCaptureDeviceInput(device: newDevice),
                  self.session.canAddInput(newInput) else {
                self.session.commitConfiguration(); return  // 切换失败，不更新 UI 状态
            }
            self.session.addInput(newInput)
            self.currentDevice = newDevice

            // 切换设备后重新协商 preset：前后摄对 1080p 的支持可能不同
            if self.isVideoMode {
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                } else if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                }
            }
            // ✅ 在 sessionQueue 中同步更新 visionService，确保新摄像头首帧前 isFrontCamera 已就绪
            self.visionService.isFrontCamera = !currentlyFront
            self.session.commitConfiguration()

            // 切换后重新固定 videoOrientation 及镜像（commitConfiguration 后 connection 仍存在）
            let isFront = !currentlyFront
            if let conn = self.videoDataOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = isFront }
            }
            // movieOutput connection 也需同步更新，否则前摄录制视频方向/镜像错乱
            if let conn = self.movieOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = isFront }
            }
            // ✅ photoOutput 同步镜像状态：前置拍照保存非镜像（与苹果原相机一致）
            if let conn = self.photoOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
            }

            // 切换后重新发布实际宽高比（前/后摄 activeFormat 可能不同）
            self.updatePreviewAspectRatio()

            DispatchQueue.main.async {
                self.isFrontCamera = !currentlyFront
                self.zoomLevel = 1.0
            }
        }
    }

    // MARK: - 拍照

    func capturePhoto() {
        guard !isCapturingPhoto else { return }
        isCapturingPhoto = true
        triggerShutter()
    }

    /// 连拍：快速拍摄 count 张，间隔 0.28 s
    func captureBurst(count: Int = 5) {
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.28) { [weak self] in
                self?.triggerShutter()
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func triggerShutter() {
        let settings = AVCapturePhotoSettings()
        if let device = currentDevice, device.hasFlash {
            settings.flashMode = flashMode
        }
        DispatchQueue.main.async { [weak self] in
            self?.showFlash = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) { self?.showFlash = false }
            }
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - 闪光灯

    func toggleFlash() {
        switch flashMode {
        case .off:  flashMode = .on
        case .on:   flashMode = .auto
        case .auto: flashMode = .off
        @unknown default: flashMode = .off
        }
    }

    var flashIcon: String {
        switch flashMode {
        case .off:  return "bolt.slash.fill"
        case .on:   return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    // MARK: - 缩放

    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
        let clamped = min(max(factor, 1.0), maxZoom)
        // Dispatch to sessionQueue to avoid blocking main thread on lockForConfiguration
        sessionQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async { self?.zoomLevel = clamped }
            } catch {}
        }
    }

    // MARK: - 对焦

    /// point 为归一化坐标 (0...1, 0...1)，由 preview layer 转换后传入
    func focusAt(point: CGPoint) {
        guard let device = currentDevice,
              device.isFocusPointOfInterestSupported,
              device.isExposurePointOfInterestSupported else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try device.lockForConfiguration()
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
                device.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in self?.isFocusing = true }
            } catch { return }

            // 2 秒后恢复连续自动对焦
            focusResetWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let device = self.currentDevice else { return }
                do {
                    try device.lockForConfiguration()
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                    device.unlockForConfiguration()
                } catch {}
                DispatchQueue.main.async { self.isFocusing = false }
            }
            self.focusResetWorkItem = workItem
            self.sessionQueue.asyncAfter(deadline: .now() + 2.0, execute: workItem)
        }  // sessionQueue.async
    }

    // MARK: - 录像

    func startRecording() {
        guard !isRecording else { return }
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_video_\(Int(Date().timeIntervalSince1970)).mov")
        tempVideoURL = fileURL
        movieOutput.startRecording(to: fileURL, recordingDelegate: self)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording = true
            self.recordingDuration = 0
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.recordingDuration += 1
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        movieOutput.stopRecording()
        recordingTimer?.invalidate(); recordingTimer = nil
        DispatchQueue.main.async { [weak self] in self?.isRecording = false }
    }

    func stopSession() {
        if isRecording { stopRecording() }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Nil delegate BEFORE stopping to prevent frames arriving during teardown
            self.videoDataOutput.setSampleBufferDelegate(nil, queue: nil)
            self.session.stopRunning()
            DispatchQueue.main.async { [weak self] in self?.isSessionRunning = false }
        }
    }

    // MARK: - 保存（含失败反馈）

    private func savePhotoToLibrary(data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.saveErrorMessage = "请在「设置」中允许访问相册"
                    self.showSaveError = true
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.showToast = true
                        self?.sessionPhotosSaved += 1
                        let newTotal = UserDefaults.standard.integer(forKey: "totalPhotosSaved") + 1
                        UserDefaults.standard.set(newTotal, forKey: "totalPhotosSaved")
                        self?.totalPhotosSaved = newTotal
                        if let img = UIImage(data: data) { self?.lastSavedImage = img }
                        Analytics.track(Analytics.Event.photoSaved)
                    } else {
                        self?.saveErrorMessage = "照片保存失败，请稍后重试"
                        self?.showSaveError = true
                    }
                }
            }
        }
    }

    private func saveVideoToLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.saveErrorMessage = "请在「设置」中允许访问相册"
                    self.showSaveError = true
                }
                try? FileManager.default.removeItem(at: url)
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { [weak self] success, _ in
                DispatchQueue.main.async {
                    if success {
                        self?.showToast = true
                        self?.lastSavedVideoURL = url
                    } else {
                        self?.saveErrorMessage = "视频保存失败，请稍后重试"
                        self?.showSaveError = true
                    }
                }
                // 注：视频 URL 保留用于分享，分享后由调用方清理
            }
        }
    }

    var formattedDuration: String {
        String(format: "%02d:%02d", Int(recordingDuration) / 60, Int(recordingDuration) % 60)
    }
}

// MARK: - Photo Delegate

extension CameraViewModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async { [weak self] in self?.isCapturingPhoto = false }
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        savePhotoToLibrary(data: data)
    }
}

// MARK: - Video Recording Delegate

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    /// 相机真正开始写文件的瞬间触发 — 不是 startRecording() 方法调用返回时
    /// View 层监听 recordingStartToken 在此时同步 PiP 参考视频
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async { [weak self] in
            self?.recordingStartToken += 1
            if let preset = self?.session.sessionPreset {
                print("[VideoRecording] didStart writing, preset=\(preset.rawValue)")
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        // 检查录制错误（app 进入后台/存储满/权限中断都会触发）
        if let error = error {
            print("[VideoRecording] error: \(error.localizedDescription)")
            // 即使报错，部分文件可能已写入，仍尝试保存（iOS 行为）
        }
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            saveVideoToLibrary(url: outputFileURL)
        }
    }
}

// MARK: - Vision 帧分析 Delegate

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard enableVisionAnalysis else { return }
        visionService.analyzeFrame(sampleBuffer)
    }
}

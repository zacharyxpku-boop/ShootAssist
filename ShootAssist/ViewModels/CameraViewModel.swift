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
    /// ⚠️ 仅用于 photoOutput / videoDataOutput。movieOutput 必须用下面的专用方法。
    private func setPortraitOrientation(_ conn: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
        } else {
            if conn.isVideoOrientationSupported { conn.videoOrientation = .portrait }
        }
    }

    /// movieOutput connection 专用 — 强制使用 videoOrientation（旧 API）
    /// 根因文档：AVCaptureMovieFileOutput 在 iOS 17+ 仍然不认 videoRotationAngle，
    /// 只有 videoOrientation 能让写入的 .mov 文件携带正确的旋转元数据。
    /// 之前两轮修复全部调的 setPortraitOrientation，在 iOS 17 走进了
    /// videoRotationAngle 分支，movieOutput 直接忽略，导致横屏。
    private func setMovieOutputPortrait(_ conn: AVCaptureConnection) {
        if conn.isVideoOrientationSupported {
            conn.videoOrientation = .portrait
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
        case .high, .medium, .low, .inputPriority:
            // .inputPriority 用于前摄手动选 format，比例由 activeFormat 决定
            // .high/.medium/.low 也不确定，一律 fallback 到 activeFormat 读
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

            self.session.commitConfiguration()
            self.session.startRunning()
            self.isConfigured = true

            // ⚠️ 关键时序修复：connection 的 orientation / mirroring 必须在
            // session.startRunning() 之后设置才能稳定生效。
            // 之前放在 commitConfiguration 之前，某些机型（A14/A15）iOS 17 上会被
            // session 启动过程 reset 回默认 landscape right，导致录制出的 .mov 文件
            // 方向错乱。实测把这段挪到 startRunning 之后可以彻底修复横屏 bug。
            if let conn = self.videoDataOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
            }
            // ✅ movieOutput 必须用 videoOrientation（旧 API），不能用 videoRotationAngle
            if let conn = self.movieOutput.connection(with: .video) {
                self.setMovieOutputPortrait(conn)
            }
            if let conn = self.photoOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
            }

            self.applyGeometricDistortionCorrectionIfSupported(to: camera)

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

            // 前后摄走不同策略：
            // - 前摄：sessionPreset = .inputPriority，手动选窄 FOV format
            //   （Apple 原相机的做法，避免 87° TrueDepth 超广角透视拉伸）
            // - 后摄：保持标准 preset（.photo / .hd1920x1080）
            let switchingToFront = !currentlyFront
            // 前摄 + 视频模式：用 .inputPriority 手动选窄 FOV format（防超广角畸变）
            // 前摄 + 照片模式：保持 .photo preset（iOS 自己选最佳 4:3 format，不干涉）
            if switchingToFront && self.isVideoMode {
                if self.session.canSetSessionPreset(.inputPriority) {
                    self.session.sessionPreset = .inputPriority
                }
            } else if switchingToFront && !self.isVideoMode {
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                }
            } else if self.isVideoMode {
                if self.session.canSetSessionPreset(.hd1920x1080) {
                    self.session.sessionPreset = .hd1920x1080
                } else if self.session.canSetSessionPreset(.hd1280x720) {
                    self.session.sessionPreset = .hd1280x720
                }
            } else {
                if self.session.canSetSessionPreset(.photo) {
                    self.session.sessionPreset = .photo
                }
            }
            // ✅ 在 sessionQueue 中同步更新 visionService，确保新摄像头首帧前 isFrontCamera 已就绪
            self.visionService.isFrontCamera = !currentlyFront
            self.session.commitConfiguration()

            let isFront = !currentlyFront

            // ── 关键时序：format 选择必须在 orientation 设置之前 ──
            // selectOptimalFrontFormat 会 lockForConfig 改 activeFormat
            // 改完之后 connection 的 videoOrientation 可能被 reset 回默认
            // 所以 orientation + mirroring 必须放在 format 选择之后

            // Step 1: 前摄+视频模式才选窄 FOV format（照片模式 .photo preset 已自带适配）
            if isFront && self.isVideoMode {
                self.selectOptimalFrontFormat(for: newDevice)
            }
            self.applyGeometricDistortionCorrectionIfSupported(to: newDevice)

            // Step 2: 设定 orientation 和 mirroring（必须在 format 选择后）
            if let conn = self.videoDataOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = isFront }
            }
            if let conn = self.movieOutput.connection(with: .video) {
                self.setMovieOutputPortrait(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = isFront }
            }
            if let conn = self.photoOutput.connection(with: .video) {
                self.setPortraitOrientation(conn)
                if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
            }

            // Step 3: 发布宽高比（必须在 format 选择后才能读到正确值）
            self.updatePreviewAspectRatio()

            // zoom 策略：前摄若 selectOptimalFrontFormat 成功（已窄 FOV）→ 1.0x
            //           否则 → 2.0x fallback
            // 判定依据：activeFormat 的 FOV ≤ 75 认为 format 选择成功
            let formatSuccess = isFront && newDevice.activeFormat.videoFieldOfView <= 75
            let targetZoom: CGFloat = (isFront && !formatSuccess) ? 2.0 : 1.0
            do {
                try newDevice.lockForConfiguration()
                let clampedZoom = min(max(targetZoom, 1.0), newDevice.maxAvailableVideoZoomFactor)
                newDevice.videoZoomFactor = clampedZoom
                newDevice.unlockForConfiguration()
                DispatchQueue.main.async { [weak self] in
                    self?.zoomLevel = clampedZoom
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.zoomLevel = 1.0
                }
            }

            // 诊断日志：前摄切换完成瞬间打印 7 项关键值
            if isFront {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // 从 UIWindow 里找 AVCaptureVideoPreviewLayer（诊断用，生产环境无副作用）
                    let previewLayer = self.findPreviewLayer()
                    self.logFrontCameraDiagnostics(device: newDevice, previewLayer: previewLayer)
                }
            }

            DispatchQueue.main.async {
                self.isFrontCamera = !currentlyFront
            }
        }
    }

    /// 遍历当前 app 的 window scene，找到第一个 AVCaptureVideoPreviewLayer
    /// 仅诊断用：前摄切换后需要读 layer.bounds 和 videoGravity
    private func findPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first else {
            return nil
        }
        return searchPreviewLayer(in: window.layer)
    }

    private func searchPreviewLayer(in layer: CALayer) -> AVCaptureVideoPreviewLayer? {
        if let preview = layer as? AVCaptureVideoPreviewLayer { return preview }
        for sub in layer.sublayers ?? [] {
            if let found = searchPreviewLayer(in: sub) { return found }
        }
        return nil
    }

    /// 若当前 activeFormat 支持几何畸变校正，则开启之。
    /// 这是前置广角镜头桶形畸变的官方软件补偿开关，iOS 13+。
    /// 不是所有机型 / 不是所有 format 都支持，调用前必须 guard。
    private func applyGeometricDistortionCorrectionIfSupported(to device: AVCaptureDevice) {
        guard device.isGeometricDistortionCorrectionSupported else { return }
        do {
            try device.lockForConfiguration()
            device.isGeometricDistortionCorrectionEnabled = true
            device.unlockForConfiguration()
        } catch {
            print("[Camera] GDC enable failed: \(error)")
        }
    }

    /// H2 核心修复：前摄专用窄视角 format 选择
    /// iPhone 前摄默认 format 常为超广角 TrueDepth（~87° FOV），导致透视拉伸。
    /// Apple 原相机会主动切到 55-75° FOV 的窄视角 format，等效焦段 ~28mm。
    /// 本方法遍历 device.formats，选出 FOV 最小但 ≥55° 的高分辨率 format 并激活。
    /// 必须配合 sessionPreset = .inputPriority 使用，否则 iOS 会用 preset 覆盖。
    private func selectOptimalFrontFormat(for device: AVCaptureDevice) {
        let candidates = device.formats.filter { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxDim = max(dims.width, dims.height)
            let minDim = min(dims.width, dims.height)
            let fov = format.videoFieldOfView
            // 支持 30fps
            let supports30 = format.videoSupportedFrameRateRanges.contains { range in
                range.minFrameRate <= 30 && range.maxFrameRate >= 30
            }
            // 分辨率 ≥ 720p
            let goodRes = maxDim >= 1280 && minDim >= 720
            // FOV 落在 55-80° 区间（太窄丢画面，太宽继续变形）
            let goodFOV = fov >= 55 && fov <= 80
            return supports30 && goodRes && goodFOV
        }

        // 选 FOV 最小的（视角最窄 = 透视最自然），同 FOV 选最高分辨率
        guard let best = candidates.min(by: { a, b in
            if a.videoFieldOfView != b.videoFieldOfView {
                return a.videoFieldOfView < b.videoFieldOfView
            }
            let aDims = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let bDims = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return (Int(aDims.width) * Int(aDims.height)) > (Int(bDims.width) * Int(bDims.height))
        }) else {
            print("[Camera] ⚠️ No suitable narrow-FOV format for front camera, falling back to default")
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            // 锁 30fps
            let target = CMTimeMake(value: 1, timescale: 30)
            device.activeVideoMinFrameDuration = target
            device.activeVideoMaxFrameDuration = target
            device.unlockForConfiguration()
            let dims = CMVideoFormatDescriptionGetDimensions(best.formatDescription)
            print("[Camera] ✅ Front format: \(dims.width)x\(dims.height) FOV=\(best.videoFieldOfView)°")
        } catch {
            print("[Camera] selectOptimalFrontFormat lock failed: \(error)")
        }
    }

    /// 诊断日志：前摄切换完成后打印 7 项关键值
    /// 真机测试时直接看 Xcode console 或 Console.app，所有值一次打印
    private func logFrontCameraDiagnostics(device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer?) {
        let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let fov = device.activeFormat.videoFieldOfView
        let preset = self.session.sessionPreset.rawValue
        let layerBounds = previewLayer?.bounds ?? .zero
        let gravity = previewLayer?.videoGravity.rawValue ?? "nil"
        let ratio = self.previewAspectRatio

        print("""

        ╔══════════════════════════════════════════════════════════════
        ║ [FrontCameraDiagnostics]
        ║ 1. activeFormat dims: \(dims.width) x \(dims.height)
        ║ 2. sessionPreset:     \(preset)
        ║ 3. previewLayer bounds: \(layerBounds)
        ║ 4. videoGravity:      \(gravity)
        ║ 5. previewAspectRatio: \(ratio)
        ║ 6. FOV:               \(fov)°
        ║ 7. photoOutput natSize: (see next capture output)
        ╚══════════════════════════════════════════════════════════════

        """)
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
        // 主线程 capture @Published isFrontCamera，避免 sessionQueue 里读主线程状态的数据竞争
        let isFront = isFrontCamera

        // 所有 movieOutput 配置和启动必须在 sessionQueue 上执行，避免和 session 配置竞态
        // 同时在这里 refresh 一次 videoRotationAngle/videoOrientation —
        // 之前在 setupSession 里 commitConfiguration 之前设过一次，但某些机型在 session 运行后
        // connection 会回退到默认（landscape right），导致导出视频变横向
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // ✅ 录制前最终兜底：强制 videoOrientation = .portrait
            if let conn = self.movieOutput.connection(with: .video) {
                self.setMovieOutputPortrait(conn)
                if conn.isVideoMirroringSupported {
                    conn.isVideoMirrored = isFront
                }
            }
            self.movieOutput.startRecording(to: fileURL, recordingDelegate: self)
        }

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
        // 诊断第 7 项：解码实际拍出的照片尺寸，看和预览比例是否对齐
        if let image = UIImage(data: data) {
            print("[Camera] 📸 Captured photo size: \(image.size), scale=\(image.scale), orientation=\(image.imageOrientation.rawValue)")
        }
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
        if let error = error {
            print("[VideoRecording] error: \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: outputFileURL.path) else { return }

        // 终极保险：检查视频 track 的实际方向，如果是横屏就用 AVMutableComposition 修正
        Task {
            let correctedURL = await Self.ensurePortraitOrientation(fileURL: outputFileURL)
            await MainActor.run { [weak self] in
                self?.saveVideoToLibrary(url: correctedURL)
            }
        }
    }

    /// 检查视频文件是否为竖屏；若为横屏则重新 mux 加 90° 旋转 transform
    @MainActor
    private static func ensurePortraitOrientation(fileURL: URL) async -> URL {
        let asset = AVURLAsset(url: fileURL)
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            print("[VideoOrientation] no video track, skipping correction")
            return fileURL
        }

        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
        do {
            naturalSize = try await videoTrack.load(.naturalSize)
            preferredTransform = try await videoTrack.load(.preferredTransform)
        } catch {
            print("[VideoOrientation] failed to load track props: \(error)")
            return fileURL
        }

        // 判断方向：应用 transform 后的尺寸，portrait 意味着 height > width
        let transformedSize = naturalSize.applying(preferredTransform)
        let w = abs(transformedSize.width)
        let h = abs(transformedSize.height)
        if h >= w {
            print("[VideoOrientation] already portrait (\(w)x\(h)), no correction needed")
            return fileURL
        }

        // 横屏！重新 mux
        print("[VideoOrientation] ⚠️ landscape detected (\(w)x\(h)), re-muxing to portrait...")
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { return fileURL }

        do {
            let duration = try await asset.load(.duration)
            try compositionVideoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: videoTrack, at: .zero
            )
        } catch {
            print("[VideoOrientation] insertTimeRange failed: \(error)")
            return fileURL
        }

        // 旋转 90° CW → portrait
        let rotateTransform = CGAffineTransform(rotationAngle: .pi / 2)
            .translatedBy(x: 0, y: -naturalSize.width)
        compositionVideoTrack.preferredTransform = rotateTransform

        // 拷贝音频 track
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
               withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let duration = try? await asset.load(.duration)
            if let duration {
                try? compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack, at: .zero
                )
            }
        }

        // 导出
        let correctedURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("sa_video_corrected_\(Int(Date().timeIntervalSince1970)).mov")
        guard let exportSession = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
        ) else { return fileURL }

        exportSession.outputURL = correctedURL
        exportSession.outputFileType = .mov
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously { continuation.resume() }
        }

        if exportSession.status == .completed {
            try? FileManager.default.removeItem(at: fileURL) // 删原横屏文件
            print("[VideoOrientation] ✅ re-muxed to portrait: \(correctedURL.lastPathComponent)")
            return correctedURL
        } else {
            print("[VideoOrientation] export failed: \(String(describing: exportSession.error))")
            return fileURL  // fallback 保存原文件
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

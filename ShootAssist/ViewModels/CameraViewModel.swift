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
    @Published var lastSavedImage: UIImage? = nil
    @Published var lastSavedVideoURL: URL? = nil

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

            let preset: AVCaptureSession.Preset = self.isVideoMode ? .high : .photo
            if self.session.canSetSessionPreset(preset) { self.session.sessionPreset = preset }

            // 视频输入
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input  = try? AVCaptureDeviceInput(device: camera) else {
                self.session.commitConfiguration(); return
            }
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.currentDevice = camera
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

            DispatchQueue.main.async {
                self.isSessionRunning = true
                self.isFrontCamera = false
            }
        }
    }

    // MARK: - 切换摄像头

    func switchCamera() {
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

            let newPosition: AVCaptureDevice.Position = self.isFrontCamera ? .back : .front
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let newInput  = try? AVCaptureDeviceInput(device: newDevice) else {
                self.session.commitConfiguration(); return
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentDevice = newDevice
            }
            self.session.commitConfiguration()

            DispatchQueue.main.async {
                self.isFrontCamera.toggle()
                self.visionService.isFrontCamera = self.isFrontCamera
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
        DispatchQueue.main.async {
            self.showFlash = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.3)) { self.showFlash = false }
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
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isSessionRunning = false }
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
                        if let img = UIImage(data: data) { self?.lastSavedImage = img }
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
        DispatchQueue.main.async { self.isCapturingPhoto = false }
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        savePhotoToLibrary(data: data)
    }
}

// MARK: - Video Recording Delegate

extension CameraViewModel: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
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

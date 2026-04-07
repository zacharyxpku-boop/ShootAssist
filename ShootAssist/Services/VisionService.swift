import SwiftUI
import Vision
import AVFoundation

// MARK: - 构图建议
struct CompositionAdvice: Equatable {
    let isGood: Bool
    let tips: [String]
    let personBox: CGRect
    let suggestedAction: String
    let headTopMargin: CGFloat
    let isCutOff: Bool

    static let empty = CompositionAdvice(
        isGood: false, tips: [], personBox: .zero,
        suggestedAction: "等待检测人物...", headTopMargin: 0, isCutOff: false
    )

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isGood == rhs.isGood && lhs.suggestedAction == rhs.suggestedAction
    }
}

// MARK: - Vision 服务（线程安全版本）
class VisionService: NSObject, ObservableObject {
    @Published var isPersonDetected = false
    @Published var personBoundingBox: CGRect = .zero
    @Published var faceBoundingBox: CGRect = .zero
    @Published var isFaceDetected = false
    @Published var compositionAdvice: CompositionAdvice = .empty
    @Published var bodyJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var jointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]
    @Published var completedPose: CompletedPose?

    @Published var isLowLightWarning: Bool = false  // 连续失败 → 光线不足提示

    private var frameCount: Int = 0
    private var consecutiveNoPersonFrames: Int = 0
    private let lowLightThreshold = 30  // 6 秒（30帧 × 5帧间隔 × 0.2s/帧 ≈ 6s）无人 → 提示
    var analyzeEveryNFrames: Int = 5

    /// EMA 平滑系数（0~1，越大越跟随新值，越小越平滑稳定）
    /// 0.35：在快速动作响应性和稳定性之间取得平衡
    var smoothingAlpha: CGFloat = 0.35
    private var smoothedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    /// 是否为前置摄像头（影响坐标方向）
    var isFrontCamera: Bool = false

    // MARK: - New state properties
    private var lastKnownJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    private var jointLastSeenFrame: [VNHumanBodyPoseObservation.JointName: Int] = [:]
    private let maxMissingFrames = 10
    static let allJointNames: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee,
        .leftAnkle, .rightAnkle, .root
    ]

    private let completionService = PoseCompletionService()

    // MARK: - 分析一帧（线程安全：每次创建新 Request，不复用）
    func analyzeFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCount += 1
        guard frameCount % analyzeEveryNFrames == 0 else { return }

        // 使用 CVPixelBuffer 而非直接传 CMSampleBuffer：避免 VNImageRequestHandler 持有
        // sampleBuffer 引用导致累积内存泄漏（iOS 17+ 会触发 Jetsam 强杀）
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // 前摄用 .upMirrored：告知 Vision 输入帧是水平镜像的（dataOutput 不自动镜像）
        // Vision 内部自动校正坐标，输出坐标可直接对应预览层（预览层对前摄自动镜像）
        // 后摄用 .up：无需任何变换
        let orientation: CGImagePropertyOrientation = isFrontCamera ? .upMirrored : .up
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)

        // 每次创建新的 Request 实例——避免跨线程复用导致数据竞争
        let personReq = VNDetectHumanRectanglesRequest()
        let faceReq = VNDetectFaceRectanglesRequest()
        let poseReq = VNDetectHumanBodyPoseRequest()

        do {
            try handler.perform([personReq, faceReq, poseReq])
        } catch {
            return
        }

        // 在当前线程（visionQueue）提取结果，然后切主线程更新 UI
        let personResult = personReq.results?.first
        let faceResult = faceReq.results?.first
        let poseResult = poseReq.results?.first

        let personBox = personResult?.boundingBox ?? .zero
        let hasPerson = personResult != nil
        let faceBox = faceResult?.boundingBox ?? .zero
        let hasFace = faceResult != nil
        // .upMirrored 时 Vision 已自动校正坐标，无需手动翻转
        let rawJoints = poseResult.flatMap { self.extractJoints(from: $0) } ?? [:]
        
        // Use PoseCompletionService to merge, interpolate, and build sources
        let completed = completionService.complete(
            rawJoints,
            boundingBox: hasPerson ? personBox : nil,
            lastKnownJoints: self.lastKnownJoints,
            frameCount: self.frameCount,
            jointLastSeenFrame: self.jointLastSeenFrame,
            maxMissingFrames: self.maxMissingFrames
        )
        
        // Update temporal memory from completed pose
        for (joint, pt) in completed.joints where completed.jointSources[joint] == .detected {
            self.lastKnownJoints[joint] = pt
            self.jointLastSeenFrame[joint] = self.frameCount
        }

        // Apply EMA smoothing to completed.joints (not raw or merged)
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (key, newPt) in completed.joints {
            if let prev = self.smoothedJoints[key] {
                joints[key] = CGPoint(
                    x: self.smoothingAlpha * newPt.x + (1 - self.smoothingAlpha) * prev.x,
                    y: self.smoothingAlpha * newPt.y + (1 - self.smoothingAlpha) * prev.y
                )
            } else {
                joints[key] = newPt  // 首次出现，直接使用原始值
            }
        }
        // Key points disappear → clear smoothed state for that joint
        self.smoothedJoints = joints

        let advice = hasPerson ? self.analyzeComposition(personBox: personBox) : CompositionAdvice(
            isGood: false, tips: ["画面中没有检测到人物"],
            personBox: .zero, suggestedAction: "请对准人物 📷",
            headTopMargin: 0, isCutOff: false
        )

        // 连续无人帧计数 → 低光/无人提示
        if hasPerson {
            consecutiveNoPersonFrames = 0
        } else {
            consecutiveNoPersonFrames += 1
        }
        let shouldWarnLowLight = consecutiveNoPersonFrames >= lowLightThreshold

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isPersonDetected = hasPerson
            self.personBoundingBox = personBox
            self.isFaceDetected = hasFace
            self.faceBoundingBox = faceBox
            self.bodyJoints = joints
            self.jointSources = completed.jointSources
            self.compositionAdvice = advice
            self.isLowLightWarning = shouldWarnLowLight
            self.completedPose = completed
        }
    }

    // MARK: - 分析静态图片 Pose (NEW SIGNATURE)
    func analyzePose(in uiImage: UIImage) -> CompletedPose {
        // Step 1: Convert UIImage orientation to CGImagePropertyOrientation
        let orientation: CGImagePropertyOrientation
        switch uiImage.imageOrientation {
        case .up: orientation = .up
        case .down: orientation = .down
        case .left: orientation = .left
        case .right: orientation = .right
        case .upMirrored: orientation = .upMirrored
        case .downMirrored: orientation = .downMirrored
        case .leftMirrored: orientation = .leftMirrored
        case .rightMirrored: orientation = .rightMirrored
        @unknown default: orientation = .up
        }

        // Step 2: First pass — full image
        guard let cgImage = uiImage.cgImage else {
            return CompletedPose(
                joints: [:],
                jointSources: [:],
                observedCount: 0,
                inferredCount: 0,
                completenessScore: 0,
                canUseForMatching: false,
                reliabilityNote: "图像无法转换为CGImage"
            )
        }

        let firstHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        let firstPoseReq = VNDetectHumanBodyPoseRequest()
        try? firstHandler.perform([firstPoseReq])
        let firstJoints = firstPoseReq.results?.first.flatMap { self.extractJoints(from: $0) } ?? [:]

        // If first pass yields ≥4 joints, return it directly
        let firstCompleted = completionService.complete(
            firstJoints,
            boundingBox: nil,
            lastKnownJoints: [:],
            frameCount: 0,
            jointLastSeenFrame: [:],
            maxMissingFrames: 10
        )
        if firstCompleted.canUseForMatching {
            return firstCompleted
        }

        // Step 3: Second pass — crop & retry
        let personHandler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
        let personReq = VNDetectHumanRectanglesRequest()
        try? personHandler.perform([personReq])
        guard let personResult = personReq.results?.first else {
            // Fallback to first pass
            return firstCompleted
        }

        let personBox = personResult.boundingBox
        // Add 20% padding
        let paddedBox = CGRect(
            x: max(0, personBox.minX - 0.1),
            y: max(0, personBox.minY - 0.1),
            width: min(1.0, personBox.width + 0.2),
            height: min(1.0, personBox.height + 0.2)
        )

        // Crop CGImage using Core Graphics
        guard let croppedCGImage = cropCGImage(cgImage, to: paddedBox, size: uiImage.size) else {
            return firstCompleted
        }

        let secondHandler = VNImageRequestHandler(cgImage: croppedCGImage, orientation: orientation)
        let secondPoseReq = VNDetectHumanBodyPoseRequest()
        try? secondHandler.perform([secondPoseReq])
        let secondJoints = secondPoseReq.results?.first.flatMap { self.extractJoints(from: $0) } ?? [:]

        // Remap second-pass joints from crop-local normalized coords back to full-image normalized coords
        let remappedSecondJoints = remapJoints(secondJoints, fromCrop: paddedBox)

        // Merge: prefer second-pass joints, fall back to first-pass
        var mergedJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for joint in Self.allJointNames {
            if let pt = remappedSecondJoints[joint] {
                mergedJoints[joint] = pt
            } else if let pt = firstJoints[joint] {
                mergedJoints[joint] = pt
            }
        }

        // Complete merged result with no last-known context (static image)
        let completed = completionService.complete(
            mergedJoints,
            boundingBox: personBox,
            lastKnownJoints: [:],
            frameCount: 0,
            jointLastSeenFrame: [:],
            maxMissingFrames: 10
        )
        return completed
    }

    // Helper to crop CGImage using normalized CGRect and original size
    private func cropCGImage(_ source: CGImage, to rect: CGRect, size: CGSize) -> CGImage? {
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let x = Int(rect.minX * width)
        let y = Int((1.0 - rect.maxY) * height) // flip Y for CGImage origin
        let w = Int(rect.width * width)
        let h = Int(rect.height * height)
        let cropRect = CGRect(x: x, y: y, width: w, height: h).integral
        guard cropRect.width > 0 && cropRect.height > 0 &&
              cropRect.maxX <= width && cropRect.maxY <= height else {
            return nil
        }
        return source.cropping(to: cropRect)
    }

    // Helper to remap joints from crop-local normalized coords back to full-image normalized coords
    private func remapJoints(_ joints: [VNHumanBodyPoseObservation.JointName: CGPoint], fromCrop cropBox: CGRect) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var result: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (joint, pt) in joints {
            result[joint] = CGPoint(
                x: cropBox.minX + pt.x * cropBox.width,
                y: cropBox.minY + pt.y * cropBox.height
            )
        }
        return result
    }

    // MARK: - 分析静态图片 Pose (LEGACY — DEPRECATED but kept for binary compat)
    func analyzePose(in image: CGImage) -> [VNHumanBodyPoseObservation.JointName: CGPoint]? {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let req = VNDetectHumanBodyPoseRequest()
        try? handler.perform([req])
        guard let observation = req.results?.first else { return nil }
        return extractJoints(from: observation)
    }

    // MARK: - 提取关键点（分关节置信度阈值，减少低置信度点引起的骨骼抖动）
    private static let jointConfidenceThresholds: [VNHumanBodyPoseObservation.JointName: Float] = [
        .nose: 0.5, .neck: 0.6,
        .leftShoulder: 0.7, .rightShoulder: 0.7,
        .leftElbow: 0.6,    .rightElbow: 0.6,
        .leftWrist: 0.5,    .rightWrist: 0.5,
        .leftHip: 0.2,      .rightHip: 0.2,   // lowered from 0.7
        .leftKnee: 0.15,    .rightKnee: 0.15, // lowered from 0.6
        .leftAnkle: 0.1,    .rightAnkle: 0.1, // lowered from 0.4
        .root: 0.2          // lowered from 0.8
    ]

    private func extractJoints(from observation: VNHumanBodyPoseObservation) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let keys = Array(Self.jointConfidenceThresholds.keys)
        for key in keys {
            let threshold = Self.jointConfidenceThresholds[key] ?? 0.3
            if let point = try? observation.recognizedPoint(key), point.confidence > threshold {
                joints[key] = CGPoint(x: point.location.x, y: point.location.y)
            }
        }
        return joints
    }

    // MARK: - 构图分析
    private func analyzeComposition(personBox: CGRect) -> CompositionAdvice {
        let centerX = personBox.midX
        let personHeight = personBox.height
        var tips: [String] = []
        var isGood = true
        var isCutOff = false

        let topMargin = 1.0 - personBox.maxY
        if topMargin < 0.03 {
            tips.append("⚠️ 头顶快出画面了！往下移一点")
            isGood = false; isCutOff = true
        } else if topMargin < 0.08 {
            tips.append("头顶留白偏少，稍微后退一点")
            isGood = false
        } else if topMargin > 0.4 {
            tips.append("头顶留白太多，靠近一些")
            isGood = false
        }

        if personBox.minY < 0.02 {
            tips.append("⚠️ 脚快被裁掉了！")
            isGood = false; isCutOff = true
        }
        if personBox.minX < 0.02 {
            tips.append("⚠️ 身体左侧快出画面了")
            isGood = false; isCutOff = true
        }
        if personBox.maxX > 0.98 {
            tips.append("⚠️ 身体右侧快出画面了")
            isGood = false; isCutOff = true
        }

        let thirdLeft: CGFloat = 1.0 / 3.0
        let thirdRight: CGFloat = 2.0 / 3.0
        if abs(centerX - thirdLeft) < 0.08 || abs(centerX - thirdRight) < 0.08 {
            tips.append("三分线构图 ✦ 很棒！")
        } else if abs(centerX - 0.5) < 0.06 {
            tips.append("居中构图 ✦ 适合对称场景")
        } else if !isCutOff {
            tips.append("往\(centerX < 0.5 ? "右" : "左")移一点，放在三分线上更好看")
            isGood = false
        }

        if personHeight > 0.85 {
            tips.append("拍全身照，手机再远一点效果更好")
        } else if personHeight > 0.55 {
            if topMargin >= 0.08 && topMargin <= 0.2 {
                tips.append("半身构图比例很棒 ✦")
            }
        } else if personHeight < 0.25 {
            tips.append("人太小了，靠近一些或者变焦")
            isGood = false
        }

        let action: String
        if isCutOff {
            action = tips.first(where: { $0.contains("⚠️") }) ?? "调整一下位置"
        } else if isGood {
            action = "构图很棒！按快门吧 ✦"
        } else {
            action = tips.first(where: { !$0.contains("✦") }) ?? "微调一下位置"
        }

        return CompositionAdvice(
            isGood: isGood, tips: tips, personBox: personBox,
            suggestedAction: action, headTopMargin: topMargin, isCutOff: isCutOff
        )
    }
}
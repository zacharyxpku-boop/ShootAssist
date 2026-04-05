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

    @Published var isLowLightWarning: Bool = false  // 连续失败 → 光线不足提示

    private var frameCount: Int = 0
    private var consecutiveNoPersonFrames: Int = 0
    private let lowLightThreshold = 30  // 6 秒（30帧 × 5帧间隔 × 0.2s/帧 ≈ 6s）无人 → 提示
    var analyzeEveryNFrames: Int = 5

    /// 是否为前置摄像头（影响坐标方向）
    var isFrontCamera: Bool = false

    // MARK: - 分析一帧（线程安全：每次创建新 Request，不复用）
    func analyzeFrame(_ sampleBuffer: CMSampleBuffer) {
        frameCount += 1
        guard frameCount % analyzeEveryNFrames == 0 else { return }

        // AVCaptureVideoDataOutput 始终提供原始未镜像帧（预览层的镜像不影响 sampleBuffer）
        // 因此 Vision 始终以 .up 处理原始帧，再在提取关节后手动翻转前摄 x 坐标
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .up)

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
        // 前摄：水平翻转 x 坐标，匹配预览层镜像（预览层对前摄自动做了水平镜像）
        var joints = poseResult.flatMap { self.extractJoints(from: $0) } ?? [:]
        if isFrontCamera {
            joints = joints.mapValues { CGPoint(x: 1.0 - $0.x, y: $0.y) }
        }
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
            self.compositionAdvice = advice
            self.isLowLightWarning = shouldWarnLowLight
        }
    }

    // MARK: - 分析静态图片 Pose
    func analyzePose(in image: CGImage) -> [VNHumanBodyPoseObservation.JointName: CGPoint]? {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let req = VNDetectHumanBodyPoseRequest()
        try? handler.perform([req])
        guard let observation = req.results?.first else { return nil }
        return extractJoints(from: observation)
    }

    // MARK: - 提取关键点
    private func extractJoints(from observation: VNHumanBodyPoseObservation) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let keys: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
            .leftAnkle, .rightAnkle,
            .root
        ]
        for key in keys {
            if let point = try? observation.recognizedPoint(key), point.confidence > 0.3 {
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

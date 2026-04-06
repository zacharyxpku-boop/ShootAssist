import Foundation
import CoreML
import Vision

// MARK: - 手势分类结果

struct GestureResult {
    let label: String       // 原始标签名
    let emoji: String?      // 对应 emoji（neutral 为 nil）
    let description: String // 中文描述
    let confidence: Float   // 置信度 0.0~1.0
}

// MARK: - 手势识别服务（CoreML + LSTM，低延迟移动端推理）

/// 基于训练好的 CoreML 模型识别手势动作序列。
/// 通过 addFrame() 持续喂入关键点数据，classify() 返回当前最可能的手势。
///
/// 使用方式（在 VideoAnalysisService 中替换规则系统）:
/// ```swift
/// let classifier = GestureClassifierService()
/// classifier.addFrame(joints: visionJoints)
/// if let result = classifier.classify() {
///     print(result.emoji, result.confidence)
/// }
/// ```
final class GestureClassifierService {

    // MARK: - 配置
    static let sequenceLength = 15   // 与训练时一致：15 帧
    static let featureDim     = 18   // 9 关节点 × 2

    /// 置信度阈值：低于此值视为"未识别"
    var confidenceThreshold: Float = 0.65

    /// 时序平滑窗口：取最近 N 次分类的众数，防止跳变
    var smoothingWindow: Int = 5

    // MARK: - 关节索引（与 collect_data.py USED_INDICES 一致）
    // Vision 关节名 → CoreML 输入特征数组索引
    private let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose,
        .leftShoulder, .rightShoulder,
        .leftElbow, .rightElbow,
        .leftWrist, .rightWrist,
        .leftHip, .rightHip,
    ]

    // MARK: - 私有状态
    private var frameBuffer: [[Float]] = []          // 滑动帧缓冲
    private var recentPredictions: [String] = []      // 平滑窗口
    private var model: MLModel?

    // MARK: - 标签 → emoji 映射（与 convert_coreml.py 一致）
    private static let labelInfo: [String: (emoji: String?, desc: String)] = [
        "raise_both_hands": ("🙌", "双手举高"),
        "point_up":         ("☝️", "指天"),
        "heart":            ("🫶", "比心"),
        "clap":             ("👏", "拍手"),
        "spread_arms":      ("🤸", "展开双臂"),
        "fly_kiss":         ("😘", "飞吻"),
        "cover_face":       ("🤭", "捂脸卖萌"),
        "hands_on_hips":    ("🤗", "叉腰"),
        "cross_arms":       ("🙅", "双手交叉"),
        "chin_rest":        ("🤔", "托腮"),
        "neutral":          (nil,   ""),
    ]

    // 标签顺序（与训练时 GESTURE_LABELS 顺序一致）
    private static let orderedLabels: [String] = [
        "raise_both_hands", "point_up", "heart", "clap",
        "spread_arms", "fly_kiss", "cover_face",
        "hands_on_hips", "cross_arms", "chin_rest", "neutral",
    ]

    // MARK: - 初始化

    init() {
        loadModel()
    }

    private func loadModel() {
        // 模型文件需要拖入 Xcode 目标（GestureClassifier.mlmodel）
        guard let modelURL = Bundle.main.url(forResource: "GestureClassifier", withExtension: "mlmodelc")
                          ?? Bundle.main.url(forResource: "GestureClassifier", withExtension: "mlmodel") else {
            // 模型文件未找到：降级使用规则系统（VideoAnalysisService.classifyPose）
            return
        }
        model = try? MLModel(contentsOf: modelURL)
    }

    /// 模型是否成功加载（False 时外部应降级到规则系统）
    var isAvailable: Bool { model != nil }

    // MARK: - 喂入新帧

    /// 将当前帧的 Vision 关键点数据加入序列缓冲。
    /// - Parameter joints: VisionService 输出的关节点字典（归一化坐标 0~1）
    func addFrame(joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) {
        var features = [Float](repeating: 0, count: Self.featureDim)
        for (arrayIdx, jointName) in jointOrder.enumerated() {
            if let pt = joints[jointName] {
                features[arrayIdx * 2]     = Float(pt.x)
                features[arrayIdx * 2 + 1] = Float(pt.y)
            }
            // 缺失关节保持为 0
        }

        frameBuffer.append(features)

        // 保持缓冲区长度 = sequenceLength（滑动窗口）
        if frameBuffer.count > Self.sequenceLength {
            frameBuffer.removeFirst()
        }
    }

    // MARK: - 推理

    /// 对当前帧缓冲进行手势分类，返回置信度最高且超阈值的结果，否则返回 nil。
    func classify() -> GestureResult? {
        guard isAvailable, frameBuffer.count == Self.sequenceLength else { return nil }

        // 构造 MLMultiArray 输入 shape: [1, sequenceLength, featureDim]
        guard let inputArray = try? MLMultiArray(shape: [1, NSNumber(value: Self.sequenceLength), NSNumber(value: Self.featureDim)], dataType: .float32) else {
            return nil
        }

        for (frameIdx, frame) in frameBuffer.enumerated() {
            for (featIdx, val) in frame.enumerated() {
                let offset = frameIdx * Self.featureDim + featIdx
                inputArray[offset] = NSNumber(value: val)
            }
        }

        // 执行推理
        let inputFeatures = try? MLDictionaryFeatureProvider(dictionary: ["keypoints": inputArray])
        guard let features = inputFeatures,
              let output = try? model?.prediction(from: features),
              let probArray = output.featureValue(for: "gesture_prob")?.multiArrayValue else {
            return nil
        }

        // 提取最高置信度
        var bestIdx = 0
        var bestConf: Float = 0
        for i in 0 ..< Self.orderedLabels.count {
            let conf = probArray[i].floatValue
            if conf > bestConf {
                bestConf = conf
                bestIdx = i
            }
        }

        let bestLabel = Self.orderedLabels[bestIdx]

        // 置信度过滤
        guard bestConf >= confidenceThreshold else { return nil }

        // 时序平滑（众数投票）
        recentPredictions.append(bestLabel)
        if recentPredictions.count > smoothingWindow {
            recentPredictions.removeFirst()
        }
        let smoothedLabel = majorityVote(recentPredictions)

        // neutral 不输出（无动作）
        if smoothedLabel == "neutral" { return nil }

        let info = Self.labelInfo[smoothedLabel] ?? (nil, smoothedLabel)
        return GestureResult(
            label: smoothedLabel,
            emoji: info.emoji,
            description: info.desc,
            confidence: bestConf
        )
    }

    /// 重置帧缓冲（切换歌曲/停止录制时调用）
    func reset() {
        frameBuffer.removeAll()
        recentPredictions.removeAll()
    }

    // MARK: - 工具

    private func majorityVote(_ arr: [String]) -> String {
        var counts: [String: Int] = [:]
        for s in arr { counts[s, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? arr.last ?? "neutral"
    }
}

// MARK: - 规则系统降级包装

extension GestureClassifierService {

    /// 当 CoreML 模型不可用时，保留原有规则系统作为兜底。
    /// VideoAnalysisService.classifyPose() 逻辑直接嵌入此处。
    func classifyWithFallback(
        joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> (emoji: String, description: String)? {
        // 1. 优先用 CoreML 模型
        addFrame(joints: joints)
        if let result = classify(), let emoji = result.emoji {
            return (emoji, result.description)
        }

        // 2. 降级：规则系统（原 VideoAnalysisService.classifyPose 逻辑）
        guard let lw = joints[.leftWrist], let rw = joints[.rightWrist] else { return nil }
        let nose = joints[.nose]
        let neck = joints[.neck]
        let lh   = joints[.leftHip]
        let rh   = joints[.rightHip]

        if let n = nose, lw.y > n.y + 0.08 && rw.y > n.y + 0.08 { return ("🙌", "双手举高") }
        if let n = nose {
            if lw.y > n.y + 0.12 { return ("☝️", "指天") }
            if rw.y > n.y + 0.12 { return ("☝️", "指天") }
        }
        if abs(lw.x - rw.x) < 0.12 && abs(lw.y - rw.y) < 0.12 {
            if let n = nose, (lw.y + rw.y) / 2 > n.y - 0.05 { return ("🫶", "比心") }
            return ("👏", "拍手")
        }
        if abs(lw.x - rw.x) > 0.45 { return ("🤸", "展开双臂") }
        if let n = nose {
            if abs(lw.y - n.y) < 0.06 && abs(lw.x - n.x) < 0.12 { return ("😘", "飞吻") }
            if abs(rw.y - n.y) < 0.06 && abs(rw.x - n.x) < 0.12 { return ("😘", "飞吻") }
        }
        if let n = nose {
            let lNear = abs(lw.y - n.y) < 0.1 && abs(lw.x - n.x) < 0.2
            let rNear = abs(rw.y - n.y) < 0.1 && abs(rw.x - n.x) < 0.2
            if lNear || rNear { return ("🤭", "捂脸卖萌") }
        }
        if let lHip = lh, let rHip = rh,
           abs(lw.y - lHip.y) < 0.1 && abs(rw.y - rHip.y) < 0.1 { return ("🤗", "叉腰") }
        if let nk = neck, lw.x > rw.x,
           abs(lw.y - nk.y) < 0.2 && abs(rw.y - nk.y) < 0.2 { return ("🙅", "双手交叉") }
        if let nk = neck, let n = nose {
            let chinY = (nk.y + n.y) / 2
            if abs(lw.y - chinY) < 0.07 { return ("🤔", "托腮") }
            if abs(rw.y - chinY) < 0.07 { return ("🤔", "托腮") }
        }

        return nil
    }
}

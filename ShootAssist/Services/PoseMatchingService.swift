import Foundation
import Vision

// MARK: - Pose 匹配结果
struct PoseMatchResult {
    let score: Float            // 0.0 ~ 1.0 整体匹配度
    let matchedJoints: Int      // 匹配的关键点数
    let totalJoints: Int        // 总共比较的关键点数
    let tips: [String]          // 调整建议
    let isMatched: Bool         // score > 阈值即为匹配
    let perJointMatch: [VNHumanBodyPoseObservation.JointName: Bool]  // 每个关键点是否匹配
    let canMatch: Bool          // false if coverage insufficient for reliable matching
    let coverageNote: String?  // human-readable coverage warning, nil if fine

    static let empty = PoseMatchResult(
        score: 0, matchedJoints: 0, totalJoints: 0,
        tips: ["等待检测..."], isMatched: false, perJointMatch: [:],
        canMatch: true, coverageNote: nil
    )
}

// MARK: - Pose 匹配服务
class PoseMatchingService {

    /// 匹配阈值：score 超过此值判定为"匹配成功"
    var matchThreshold: Float = 0.65

    /// 单个关键点匹配容差（归一化坐标距离，以肩宽为单位）
    /// 0.35 ≈ 允许约 12cm 偏差（典型肩宽 35cm），对非专业用户友好
    var jointTolerance: CGFloat = 0.35

    /// 最小所需关键点数（detected）用于可靠匹配
    var minRequiredJoints: Int = 5
    private let torsoAnchors: [VNHumanBodyPoseObservation.JointName] = [
        .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .root
    ]

    // MARK: - 核心：比较两组关键点 (overloaded)
    /// reference: 参考图（或预设 Pose）的关键点
    /// current: 实时检测到的关键点
    func comparePoses(
        reference: [VNHumanBodyPoseObservation.JointName: CGPoint],
        refSources: [VNHumanBodyPoseObservation.JointName: JointSource],
        current: [VNHumanBodyPoseObservation.JointName: CGPoint],
        curSources: [VNHumanBodyPoseObservation.JointName: JointSource]
    ) -> PoseMatchResult {

        // Coverage checks
        let detectedRefCount = refSources.filter { $0.value == .detected }.count
        let refTorsoDetected = torsoAnchors.filter { refSources[$0] == .detected }.count
        let refHasShoulderPair = refSources[.leftShoulder] == .detected && refSources[.rightShoulder] == .detected
        if detectedRefCount < minRequiredJoints || refTorsoDetected < 3 || !refHasShoulderPair {
            return PoseMatchResult(
                score: 0,
                matchedJoints: 0,
                totalJoints: 0,
                tips: [],
                isMatched: false,
                perJointMatch: [:],
                canMatch: false,
                coverageNote: "参考图躯干关键点不足，无法进行可靠匹配"
            )
        }

        let detectedCurCount = curSources.filter { $0.value == .detected }.count
        let curTorsoReliable = torsoAnchors.filter {
            let source = curSources[$0]
            return source == .detected || source == .lastKnown
        }.count
        let curHasShoulderPair = current[.leftShoulder] != nil && current[.rightShoulder] != nil
        if detectedCurCount < 3 || curTorsoReliable < 2 || !curHasShoulderPair {
            return PoseMatchResult(
                score: 0,
                matchedJoints: 0,
                totalJoints: 0,
                tips: [],
                isMatched: false,
                perJointMatch: [:],
                canMatch: false,
                coverageNote: "实时骨架覆盖不足，请调整位置后再匹配"
            )
        }

        // Generate tips for missing critical joints
        var tips: [String] = []

        if reference.keys.contains(.nose) && !current.keys.contains(.nose) {
            tips.append("头部未检测到，请正对镜头")
        }

        let hasLeftHip = current.keys.contains(.leftHip)
        let hasRightHip = current.keys.contains(.rightHip)
        if (reference.keys.contains(.leftHip) || reference.keys.contains(.rightHip)) && !hasLeftHip && !hasRightHip {
            tips.append("下半身未检测到，请退后让全身入镜")
        }

        // Normalize coordinates
        let refNorm = normalizeToTorso(reference)
        let curNorm = normalizeToTorso(current)

        guard !refNorm.isEmpty && !curNorm.isEmpty else {
            return PoseMatchResult(
                score: 0,
                matchedJoints: 0,
                totalJoints: 0,
                tips: ["未检测到完整姿势"],
                isMatched: false,
                perJointMatch: [:],
                canMatch: true,
                coverageNote: nil
            )
        }

        // Define joints to compare
        let compareJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
        ]

        var matchedWeights: Float = 0.0
        var totalWeights: Float = 0.0
        var matchedCount = 0
        var totalCount = 0
        var perJoint: [VNHumanBodyPoseObservation.JointName: Bool] = [:]

        let criticalJoints: Set<VNHumanBodyPoseObservation.JointName> = [
            .nose, .neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip
        ]

        for joint in compareJoints {
            guard let refPt = refNorm[joint] else { continue }
            totalCount += 1

            // Assign weight based on source
            let refWeight: Float = refSources[joint] == .detected ? 1.0 : 0.4
            let curWeight: Float
            switch curSources[joint] {
            case .detected?: curWeight = 1.0
            case .lastKnown?: curWeight = 0.55
            case .interpolated?: curWeight = 0.35
            case nil: curWeight = criticalJoints.contains(joint) ? 0.8 : 0.4
            }
            let jointWeight = min(refWeight, curWeight)

            totalWeights += jointWeight

            guard let curPt = curNorm[joint] else {
                if criticalJoints.contains(joint) {
                    tips.append(missingJointTip(for: joint))
                }
                perJoint[joint] = false
                continue
            }

            let dist = distance(refPt, curPt)
            let isClose = dist < jointTolerance
            perJoint[joint] = isClose

            if isClose {
                matchedWeights += jointWeight
                matchedCount += 1
            } else {
                // Generate tip only for joints present in both
                let tip = generateTip(joint: joint, refPt: refPt, curPt: curPt)
                if let tip = tip { tips.append(tip) }
            }
        }

        let weightedScore: Float = totalWeights > 0 ? matchedWeights / totalWeights : 0

        // Only keep top 3 tips
        let topTips = Array(tips.prefix(3))

        return PoseMatchResult(
            score: weightedScore,
            matchedJoints: matchedCount,
            totalJoints: totalCount,
            tips: topTips.isEmpty && weightedScore < matchThreshold ? ["继续调整姿势..."] : topTips,
            isMatched: weightedScore >= matchThreshold && detectedCurCount >= minRequiredJoints,
            perJointMatch: perJoint,
            canMatch: true,
            coverageNote: nil
        )
    }

    // MARK: - Legacy signature (backwards compatible)
    func comparePoses(
        reference: [VNHumanBodyPoseObservation.JointName: CGPoint],
        current: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> PoseMatchResult {
        // Use default sources where every joint in the dict defaults to .detected
        let defaultRefSources = reference.mapValues { _ in JointSource.detected }
        let defaultCurSources = current.mapValues { _ in JointSource.detected }
        return comparePoses(
            reference: reference,
            refSources: defaultRefSources,
            current: current,
            curSources: defaultCurSources
        )
    }

    // MARK: - 归一化：以躯干为中心的相对坐标
    private func normalizeToTorso(
        _ joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        // 取肩膀中心作为原点
        guard let ls = joints[.leftShoulder], let rs = joints[.rightShoulder] else {
            return joints // fallback：不归一化
        }
        let center = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
        let shoulderWidth = distance(ls, rs)
        let scale: CGFloat = shoulderWidth > 0.01 ? shoulderWidth : 1.0

        var normalized: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        for (key, pt) in joints {
            normalized[key] = CGPoint(
                x: (pt.x - center.x) / scale,
                y: (pt.y - center.y) / scale
            )
        }
        return normalized
    }

    // MARK: - 生成调整建议
    private func generateTip(
        joint: VNHumanBodyPoseObservation.JointName,
        refPt: CGPoint,
        curPt: CGPoint
    ) -> String? {
        let dx = refPt.x - curPt.x
        let dy = refPt.y - curPt.y

        let jointName: String
        switch joint {
        case .leftWrist: jointName = "左手"
        case .rightWrist: jointName = "右手"
        case .leftElbow: jointName = "左臂"
        case .rightElbow: jointName = "右臂"
        case .leftShoulder: jointName = "左肩"
        case .rightShoulder: jointName = "右肩"
        case .nose: jointName = "头"
        case .leftHip, .rightHip: jointName = "身体"
        case .leftKnee: jointName = "左腿"
        case .rightKnee: jointName = "右腿"
        default: return nil
        }

        // 判断主方向
        if abs(dx) > abs(dy) {
            return "\(jointName)往\(dx > 0 ? "右" : "左")移一点"
        } else {
            return "\(jointName)\(dy > 0 ? "抬高" : "放低")一点"
        }
    }

    // MARK: - 两点距离
    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
    }

    private func missingJointTip(for joint: VNHumanBodyPoseObservation.JointName) -> String {
        switch joint {
        case .nose: return "头部未检测到，请正对镜头"
        case .neck, .leftShoulder, .rightShoulder: return "上半身未稳定检测到，请保持肩部入镜"
        case .leftHip, .rightHip: return "下半身未检测到，请退后让髋部入镜"
        default: return "关键点缺失，请调整姿势"
        }
    }
}

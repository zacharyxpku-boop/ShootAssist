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

    static let empty = PoseMatchResult(
        score: 0, matchedJoints: 0, totalJoints: 0,
        tips: ["等待检测..."], isMatched: false, perJointMatch: [:]
    )
}

// MARK: - Pose 匹配服务
class PoseMatchingService {

    /// 匹配阈值：score 超过此值判定为"匹配成功"
    var matchThreshold: Float = 0.65

    /// 单个关键点匹配容差（归一化坐标距离，以肩宽为单位）
    /// 0.35 ≈ 允许约 12cm 偏差（典型肩宽 35cm），对非专业用户友好
    var jointTolerance: CGFloat = 0.35

    // MARK: - 核心：比较两组关键点
    /// reference: 参考图（或预设 Pose）的关键点
    /// current: 实时检测到的关键点
    func comparePoses(
        reference: [VNHumanBodyPoseObservation.JointName: CGPoint],
        current: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> PoseMatchResult {

        // 先做归一化——将两组关键点都转换为"以躯干中心为原点、以肩宽为单位"的相对坐标
        let refNorm = normalizeToTorso(reference)
        let curNorm = normalizeToTorso(current)

        guard !refNorm.isEmpty && !curNorm.isEmpty else {
            return PoseMatchResult(
                score: 0, matchedJoints: 0, totalJoints: 0,
                tips: ["未检测到完整姿势"], isMatched: false, perJointMatch: [:]
            )
        }

        // 要比较的关键点
        let compareJoints: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip,
            .leftKnee, .rightKnee,
        ]

        var matched = 0
        var total = 0
        var tips: [String] = []
        var perJoint: [VNHumanBodyPoseObservation.JointName: Bool] = [:]

        for joint in compareJoints {
            guard let refPt = refNorm[joint], let curPt = curNorm[joint] else { continue }
            total += 1
            let dist = distance(refPt, curPt)
            let isClose = dist < jointTolerance
            perJoint[joint] = isClose

            if isClose {
                matched += 1
            } else {
                // 生成具体的调整建议
                let tip = generateTip(joint: joint, refPt: refPt, curPt: curPt)
                if let tip = tip { tips.append(tip) }
            }
        }

        let score: Float = total > 0 ? Float(matched) / Float(total) : 0

        // 只保留最关键的 3 条建议
        let topTips = Array(tips.prefix(3))

        return PoseMatchResult(
            score: score,
            matchedJoints: matched,
            totalJoints: total,
            tips: topTips.isEmpty && score < matchThreshold ? ["继续调整姿势..."] : topTips,
            isMatched: score >= matchThreshold,
            perJointMatch: perJoint
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
}

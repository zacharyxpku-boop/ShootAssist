import SwiftUI
import Vision

// MARK: - 真正的人体骨骼渲染（基于 Vision VNHumanBodyPoseObservation 关键点）
struct PoseSkeletonView: View {
    /// Vision 检测到的关键点（归一化坐标，Y 朝上）
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// 容器尺寸（用于坐标转换）
    let viewSize: CGSize
    /// 线条颜色
    var lineColor: Color = .rosePink
    /// 线宽
    var lineWidth: CGFloat = 2.5
    /// 关键点圆点大小
    var jointRadius: CGFloat = 4
    /// 是否为参考图骨骼（半透明虚线）
    var isReference: Bool = false

    // MARK: - 骨骼连接定义（哪些关键点之间要画线）
    private static let bones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // 头 → 脖子
        (.nose, .neck),
        // 脖子 → 左肩 → 左肘 → 左手腕
        (.neck, .leftShoulder),
        (.leftShoulder, .leftElbow),
        (.leftElbow, .leftWrist),
        // 脖子 → 右肩 → 右肘 → 右手腕
        (.neck, .rightShoulder),
        (.rightShoulder, .rightElbow),
        (.rightElbow, .rightWrist),
        // 脖子 → 躯干中心
        (.neck, .root),
        // 躯干 → 左髋 → 左膝 → 左脚踝
        (.root, .leftHip),
        (.leftHip, .leftKnee),
        (.leftKnee, .leftAnkle),
        // 躯干 → 右髋 → 右膝 → 右脚踝
        (.root, .rightHip),
        (.rightHip, .rightKnee),
        (.rightKnee, .rightAnkle),
        // 肩膀连线
        (.leftShoulder, .rightShoulder),
        // 髋部连线
        (.leftHip, .rightHip),
    ]

    var body: some View {
        Canvas { context, size in
            let opacity: Double = isReference ? 0.55 : 0.85

            // 画骨骼线
            for (jointA, jointB) in Self.bones {
                guard let pointA = joints[jointA],
                      let pointB = joints[jointB] else { continue }

                let a = convertPoint(pointA)
                let b = convertPoint(pointB)

                var path = Path()
                path.move(to: a)
                path.addLine(to: b)

                if isReference {
                    // 参考图骨骼用虚线
                    context.stroke(path, with: .color(lineColor.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: lineWidth, dash: [6, 4]))
                } else {
                    // 实时骨骼用实线
                    context.stroke(path, with: .color(lineColor.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

            // 画关键点圆点
            for (jointName, point) in joints {
                let p = convertPoint(point)
                let dotColor = jointDotColor(for: jointName)
                let rect = CGRect(x: p.x - jointRadius, y: p.y - jointRadius,
                                  width: jointRadius * 2, height: jointRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(opacity)))

                // 关键点外圈（白色描边增加可见性）
                if !isReference {
                    let outerRect = CGRect(x: p.x - jointRadius - 1, y: p.y - jointRadius - 1,
                                           width: (jointRadius + 1) * 2, height: (jointRadius + 1) * 2)
                    context.stroke(Path(ellipseIn: outerRect),
                                   with: .color(.white.opacity(0.4)),
                                   lineWidth: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - 坐标转换（Vision 归一化 → SwiftUI 屏幕坐标）
    private func convertPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: point.x * viewSize.width,
            y: (1 - point.y) * viewSize.height  // Vision Y 朝上，SwiftUI Y 朝下
        )
    }

    // MARK: - 不同关键点用不同颜色
    private func jointDotColor(for joint: VNHumanBodyPoseObservation.JointName) -> Color {
        switch joint {
        case .nose: return .white
        case .neck: return .white
        case .leftShoulder, .leftElbow, .leftWrist: return Color(hex: "FF85A1")  // 左侧粉色
        case .rightShoulder, .rightElbow, .rightWrist: return Color(hex: "FFCBA4")  // 右侧橙色
        case .leftHip, .leftKnee, .leftAnkle: return Color(hex: "FF85A1")
        case .rightHip, .rightKnee, .rightAnkle: return Color(hex: "FFCBA4")
        case .root: return .white
        default: return lineColor
        }
    }
}

// MARK: - 简化版：只显示上半身（用于手势舞模式）
struct UpperBodySkeletonView: View {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let viewSize: CGSize
    var lineColor: Color = .green
    var lineWidth: CGFloat = 2

    private static let upperBones: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        (.nose, .neck),
        (.neck, .leftShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.neck, .rightShoulder), (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .rightShoulder),
    ]

    var body: some View {
        Canvas { context, size in
            for (jointA, jointB) in Self.upperBones {
                guard let pA = joints[jointA], let pB = joints[jointB] else { continue }
                let a = CGPoint(x: pA.x * viewSize.width, y: (1 - pA.y) * viewSize.height)
                let b = CGPoint(x: pB.x * viewSize.width, y: (1 - pB.y) * viewSize.height)
                var path = Path()
                path.move(to: a)
                path.addLine(to: b)
                context.stroke(path, with: .color(lineColor.opacity(0.7)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

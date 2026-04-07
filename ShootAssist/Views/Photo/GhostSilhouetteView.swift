import SwiftUI
import Vision

// MARK: - 通用占位人体虚影（虚线轮廓，无关键点时使用）
struct GhostSilhouetteView: View {
    var body: some View {
        ZStack {
            // 身体
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.rosePink.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.rosePink.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                )
                .frame(width: 70, height: 160)
                .offset(y: 15)

            // 头部
            Circle()
                .fill(Color.rosePink.opacity(0.05))
                .overlay(
                    Circle()
                        .stroke(
                            Color.rosePink.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                        )
                )
                .frame(width: 30, height: 30)
                .offset(y: -70)
        }
    }
}

// MARK: - 关键点驱动的参考人物轮廓（拍同款拍摄阶段使用）
struct ReferenceSilhouetteView: View {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let viewSize: CGSize
    var jointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]

    // Vision 坐标（0,0在左下）→ SwiftUI 屏幕坐标
    private func pt(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
        guard let p = joints[name] else { return nil }
        return CGPoint(x: p.x * viewSize.width, y: (1 - p.y) * viewSize.height)
    }

    private func isEstimated(_ a: VNHumanBodyPoseObservation.JointName, _ b: VNHumanBodyPoseObservation.JointName) -> Bool {
        let sourceA = jointSources[a]
        let sourceB = jointSources[b]
        return sourceA == .interpolated || sourceA == .lastKnown || sourceB == .interpolated || sourceB == .lastKnown
    }

    var body: some View {
        Canvas { ctx, _ in
            let baseColor = Color.rosePink
            let lw: CGFloat = 5

            let connections: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
                // 脊柱
                (.neck, .root),
                // 左臂
                (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
                // 右臂
                (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
                // 肩
                (.leftShoulder, .rightShoulder),
                // 肩→腰
                (.leftShoulder, .root), (.rightShoulder, .root),
                // 左腿
                (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
                // 右腿
                (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
                // 髋
                (.leftHip, .rightHip),
                // 腰→髋
                (.root, .leftHip), (.root, .rightHip),
            ]

            // 绘制连接线（厚描边，营造剪影感）
            for (a, b) in connections {
                guard let pa = pt(a), let pb = pt(b) else { continue }
                
                let isEst = isEstimated(a, b)
                let color = baseColor.opacity(isEst ? 0.3 : 0.55)
                let lineWidth = isEst ? lw * 0.7 : lw
                let strokeStyle = isEst
                    ? StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [4, 4])
                    : StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                
                var path = Path()
                path.move(to: pa)
                path.addLine(to: pb)
                ctx.stroke(path, with: .color(color), style: strokeStyle)
            }

            // 头部圆
            if let neck = pt(.neck) {
                let headR: CGFloat = lw * 3.5
                let headCenter = CGPoint(x: neck.x, y: neck.y - headR * 2.2)
                let headRect = CGRect(x: headCenter.x - headR, y: headCenter.y - headR,
                                      width: headR * 2, height: headR * 2)
                ctx.fill(Path(ellipseIn: headRect), with: .color(baseColor.opacity(0.12)))
                ctx.stroke(Path(ellipseIn: headRect), with: .color(baseColor.opacity(0.55)),
                           style: StrokeStyle(lineWidth: lw * 0.7, lineCap: .round))
            }

            // 关节节点
            for (jointName, p) in joints {
                let sp = CGPoint(x: p.x * viewSize.width, y: (1 - p.y) * viewSize.height)
                let source = jointSources[jointName]
                let radius: CGFloat = source == .detected ? lw * 0.9 : lw * 0.5
                let opacity: Double = source == .detected ? 0.55 : 0.25
                let rect = CGRect(x: sp.x - radius, y: sp.y - radius, width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(baseColor.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }
}
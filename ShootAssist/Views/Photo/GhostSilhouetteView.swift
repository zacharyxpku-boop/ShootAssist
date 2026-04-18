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

// MARK: - 可交互参考轮廓（拖拽平移 + 捏合缩放，只在骨架包围盒内响应手势）
struct InteractiveReferenceSilhouette: View {
    let joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let viewSize: CGSize
    var jointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]

    @State private var offset: CGSize = .zero
    @State private var accumOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var accumScale: CGFloat = 1.0

    // 关键点在 viewSize 坐标系下的外接矩形（头圆在 neck 上方约 38pt，加描边余量）
    private var boundingBox: CGRect {
        let pts = joints.values.map {
            CGPoint(x: $0.x * viewSize.width, y: (1 - $0.y) * viewSize.height)
        }
        guard !pts.isEmpty,
              let minX = pts.map(\.x).min(),
              let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(),
              let maxY = pts.map(\.y).max() else {
            return CGRect(x: 0, y: 0, width: max(viewSize.width, 1), height: max(viewSize.height, 1))
        }
        return CGRect(
            x: minX - 30,
            y: minY - 55,
            width: (maxX - minX) + 60,
            height: (maxY - minY) + 80
        )
    }

    // scaleEffect 以骨架中心为锚点，缩放不会漂移
    private var anchor: UnitPoint {
        guard viewSize.width > 0, viewSize.height > 0 else { return .center }
        return UnitPoint(
            x: min(max(boundingBox.midX / viewSize.width, 0), 1),
            y: min(max(boundingBox.midY / viewSize.height, 0), 1)
        )
    }

    // 用几个固定关键点做指纹 —— 同一张参考图多次渲染指纹稳定，换图必变
    // （字典迭代顺序不稳定，所以查 nose/neck/root 而不是 joints.first）
    private var referenceFingerprint: Int {
        let keys: [VNHumanBodyPoseObservation.JointName] = [.nose, .neck, .root, .leftShoulder, .rightShoulder]
        var h = 0
        for (i, k) in keys.enumerated() {
            let p = joints[k] ?? .zero
            h &+= Int(p.x * 100_000) &* (i + 1) &+ Int(p.y * 100_000) &* (i + 2)
        }
        return h &+ joints.count &* 10_000_000
    }

    var body: some View {
        ZStack {
            // 可视骨架（内部 Canvas 自带 allowsHitTesting(false)，不参与命中）
            ReferenceSilhouetteView(
                joints: joints,
                viewSize: viewSize,
                jointSources: jointSources
            )

            // 显式命中视图：替代 .contentShape + allowsHitTesting 子视图组合
            // 用带实色填充的 Rectangle（opacity=0.001 视觉不可见但参与 hit-test）
            // 这样骨架外的屏幕区域自然 pass through 到下方相机预览（tap-to-focus 不受影响）
            Rectangle()
                .fill(Color.black.opacity(0.001))
                .frame(
                    width: max(boundingBox.width, 1),
                    height: max(boundingBox.height, 1)
                )
                .position(x: boundingBox.midX, y: boundingBox.midY)
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .scaleEffect(scale, anchor: anchor)
        .offset(offset)
        // 手势挂在最外层（scaleEffect/offset 之后），translation 在屏幕坐标系，1:1 跟手
        // ZStack 只有内层 Rectangle 是 hit-testable，骨架外空白会 pass-through，不会触发此手势
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        offset = CGSize(
                            width: accumOffset.width + value.translation.width,
                            height: accumOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        accumOffset = offset
                    },
                MagnificationGesture()
                    .onChanged { value in
                        let next = accumScale * value
                        scale = min(max(next, 0.3), 3.5)
                    }
                    .onEnded { _ in
                        accumScale = scale
                    }
            )
        )
        // 换参考图时把 offset/scale 清零 —— 避免旧状态把新骨架推到屏幕外
        .onChange(of: referenceFingerprint) { _ in
            offset = .zero
            accumOffset = .zero
            scale = 1.0
            accumScale = 1.0
        }
    }
}
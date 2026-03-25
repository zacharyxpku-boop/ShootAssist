import SwiftUI
import Vision

// MARK: - 构图辅助叠加层（Vision AI 驱动，不入镜）
struct PhotoOverlayView: View {
    let subMode: PhotoSubMode
    let isShootingPhase: Bool
    let advice: CompositionAdvice
    let isPersonDetected: Bool
    let showSafetyWarning: Bool
    let safetyWarningText: String
    let guideTips: [String]
    // 实时骨骼
    let liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    // 参考图关键点
    let referenceJoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let isReferenceAnalyzed: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // MARK: - 黄金分割线（所有子模式）
                GoldenRatioGrid(size: geo.size)

                // 四角取景框
                if subMode == .influencerClone || subMode == .smartComposition {
                    CornerBrackets(size: geo.size)
                }

                // =========== 拍同款模式（拍摄阶段）===========
                if subMode == .influencerClone && isShootingPhase {
                    // 1. 参考轮廓（关键点驱动的半透明粉色剪影）
                    if !referenceJoints.isEmpty {
                        ReferenceSilhouetteView(joints: referenceJoints, viewSize: geo.size)
                    } else {
                        // 没有关键点时显示通用占位虚影
                        GhostSilhouetteView()
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.45)
                            .opacity(0.35)
                    }

                    // 2. 对齐引导文字
                    Text("调整位置，使被拍者与轮廓对齐")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .position(x: geo.size.width / 2, y: geo.size.height - 44)
                }

                // =========== 智能构图模式 ===========
                if subMode == .smartComposition {
                    // 实时骨骼线
                    if !liveJoints.isEmpty {
                        PoseSkeletonView(
                            joints: liveJoints,
                            viewSize: geo.size,
                            lineColor: advice.isGood ? .green : Color(hex: "FFCBA4"),
                            lineWidth: 2,
                            jointRadius: 3,
                            isReference: false
                        )
                    }

                    // 安全警告
                    if showSafetyWarning {
                        SafetyWarningOverlay(size: geo.size, warningText: safetyWarningText)
                    }

                    // 构图建议
                    GuideBubble(text: advice.suggestedAction)
                        .position(x: geo.size.width / 2, y: geo.size.height - 40)
                }

                // =========== 机位提示模式 ===========
                if subMode == .cameraGuide {
                    if !liveJoints.isEmpty {
                        PoseSkeletonView(
                            joints: liveJoints,
                            viewSize: geo.size,
                            lineColor: .white.opacity(0.5),
                            lineWidth: 1.5,
                            jointRadius: 2.5,
                            isReference: false
                        )
                    }

                    CameraGuideCard(texts: guideTips)
                        .position(x: geo.size.width - 50, y: geo.size.height / 2)
                }
            }
        }
    }
}

// MARK: - 黄金分割线
private struct GoldenRatioGrid: View {
    let size: CGSize
    var body: some View {
        Canvas { context, _ in
            let color = Color.sakuraPink.opacity(0.22)
            for i in 1...2 {
                let y = size.height * CGFloat(i) / 3.0
                var hPath = Path(); hPath.move(to: CGPoint(x: 0, y: y)); hPath.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(hPath, with: .color(color), lineWidth: 0.8)
                let x = size.width * CGFloat(i) / 3.0
                var vPath = Path(); vPath.move(to: CGPoint(x: x, y: 0)); vPath.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(vPath, with: .color(color), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 四角取景框
private struct CornerBrackets: View {
    let size: CGSize
    private let bs: CGFloat = 18, lw: CGFloat = 2, inset: CGFloat = 16
    var body: some View {
        Canvas { ctx, _ in
            let corners: [(CGPoint, Bool, Bool)] = [
                (CGPoint(x: inset, y: inset), false, false),
                (CGPoint(x: size.width - inset, y: inset), true, false),
                (CGPoint(x: inset, y: size.height - inset), false, true),
                (CGPoint(x: size.width - inset, y: size.height - inset), true, true),
            ]
            for (pt, flipX, flipY) in corners {
                var path = Path()
                path.move(to: CGPoint(x: pt.x + (flipX ? -bs : bs), y: pt.y))
                path.addLine(to: pt)
                path.addLine(to: CGPoint(x: pt.x, y: pt.y + (flipY ? -bs : bs)))
                ctx.stroke(path, with: .color(.rosePink),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 安全警告
private struct SafetyWarningOverlay: View {
    let size: CGSize; let warningText: String
    @State private var flashOpacity: Double = 0
    var body: some View {
        ZStack {
            Rectangle().stroke(Color.red, lineWidth: 4).opacity(flashOpacity)
            VStack {
                Text(warningText)
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.8)))
                    .padding(.top, 50)
                Spacer()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) { flashOpacity = 0.7 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation { flashOpacity = 0 } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { withAnimation { flashOpacity = 0.7 } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { withAnimation { flashOpacity = 0 } }
        }
    }
}

// MARK: - 机位提示卡片
private struct CameraGuideCard: View {
    let texts: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(texts.prefix(5)), id: \.self) { text in
                Text(text).font(.system(size: 10)).tracking(0.5).foregroundColor(.white)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.6)))
        .animation(.easeInOut(duration: 0.3), value: texts)
    }
}

// MARK: - 底部提示气泡
private struct GuideBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium)).foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.rosePink.opacity(0.85)))
            .animation(.easeInOut(duration: 0.3), value: text)
    }
}

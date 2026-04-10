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
    let liveJointSources: [VNHumanBodyPoseObservation.JointName: JointSource]
    // 参考图关键点
    let referenceJoints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    let referenceJointSources: [VNHumanBodyPoseObservation.JointName: JointSource]
    let isReferenceAnalyzed: Bool
    let referenceCompleteness: Float
    let referenceReliabilityNote: String?

    // 新增：光线 + 角度coaching + 匹配分
    let lightingResult: LightingResult
    let angleCoachingTips: [String]
    let poseMatchScore: Float

    init(
        subMode: PhotoSubMode = .influencerClone,
        isShootingPhase: Bool = false,
        advice: CompositionAdvice = .empty,
        isPersonDetected: Bool = false,
        showSafetyWarning: Bool = false,
        safetyWarningText: String = "",
        guideTips: [String] = [],
        liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:],
        liveJointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:],
        referenceJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:],
        referenceJointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:],
        isReferenceAnalyzed: Bool = false,
        referenceCompleteness: Float = 1.0,
        referenceReliabilityNote: String? = nil,
        lightingResult: LightingResult = .empty,
        angleCoachingTips: [String] = [],
        poseMatchScore: Float = 0
    ) {
        self.subMode = subMode
        self.isShootingPhase = isShootingPhase
        self.advice = advice
        self.isPersonDetected = isPersonDetected
        self.showSafetyWarning = showSafetyWarning
        self.safetyWarningText = safetyWarningText
        self.guideTips = guideTips
        self.liveJoints = liveJoints
        self.liveJointSources = liveJointSources
        self.referenceJoints = referenceJoints
        self.referenceJointSources = referenceJointSources
        self.isReferenceAnalyzed = isReferenceAnalyzed
        self.referenceCompleteness = referenceCompleteness
        self.referenceReliabilityNote = referenceReliabilityNote
        self.lightingResult = lightingResult
        self.angleCoachingTips = angleCoachingTips
        self.poseMatchScore = poseMatchScore
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // MARK: - 黄金分割线（所有子模式）
                GoldenRatioGrid(size: geo.size)

                // MARK: - 光线状态徽标（左上角，所有模式可见）
                if lightingResult.quality != .unknown && lightingResult.quality != .good {
                    LightingBadge(result: lightingResult)
                        .position(x: 60, y: 52)
                }

                // 四角取景框
                if subMode == .influencerClone || subMode == .smartComposition {
                    CornerBrackets(size: geo.size)
                }

                // =========== 拍同款模式（拍摄阶段）===========
                if subMode == .influencerClone && isShootingPhase {
                    // 1. 参考轮廓（关键点驱动的半透明粉色剪影）
                    if !referenceJoints.isEmpty {
                        ReferenceSilhouetteView(joints: referenceJoints, viewSize: geo.size, jointSources: referenceJointSources)
                    } else {
                        // 没有关键点时显示通用占位虚影
                        GhostSilhouetteView()
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.45)
                            .opacity(0.35)
                    }

                    // 2. 匹配分数环 + 角度coaching（右上角）
                    if poseMatchScore > 0.01 {
                        PoseScoreRing(score: poseMatchScore, coachingTips: angleCoachingTips)
                            .position(x: geo.size.width - 50, y: 80)
                    }

                    // 3. 对齐引导文字
                    VStack(spacing: 4) {
                        Text("调整位置，使被拍者与轮廓对齐")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        
                        // Hint for interpolated parts
                        if !referenceJointSources.isEmpty && referenceCompleteness < 0.8 {
                            Text("虚线部分为 AI 补全，仅供参考")
                                .font(.system(size: 9))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4)))
                        }
                        
                        // Reliability note warning
                        if let note = referenceReliabilityNote {
                            Text(note)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 12).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.15)))
                        }
                    }
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
                            isReference: false,
                            jointSources: liveJointSources
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
                            isReference: false,
                            jointSources: liveJointSources
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

// MARK: - 光线状态徽标
private struct LightingBadge: View {
    let result: LightingResult

    private var icon: String {
        switch result.quality {
        case .backlit: return "sun.max.trianglebadge.exclamationmark"
        case .harshSide: return "sun.haze"
        case .tooDark: return "moon"
        case .tooBright: return "sun.max.fill"
        default: return "sun.min"
        }
    }

    private var badgeColor: Color {
        switch result.quality {
        case .backlit, .tooDark: return .orange
        case .harshSide: return .yellow
        case .tooBright: return .red
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(result.tips.first ?? result.quality.rawValue)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(badgeColor.opacity(0.75)))
        .animation(.easeInOut(duration: 0.5), value: result.quality.rawValue)
    }
}

// MARK: - 匹配分数环 + 角度 coaching
private struct PoseScoreRing: View {
    let score: Float
    let coachingTips: [String]

    private var ringColor: Color {
        if score >= 0.65 { return .green }
        if score >= 0.4 { return .yellow }
        return .orange
    }

    var body: some View {
        VStack(spacing: 6) {
            // 圆环分数
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(score))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 44, height: 44)
                    .rotationEffect(.degrees(-90))
                Text("\(Int(score * 100))")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 0.3), value: score)

            // 角度调整提示
            if !coachingTips.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(coachingTips, id: \.self) { tip in
                        Text(tip)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.55)))
            }
        }
    }
}
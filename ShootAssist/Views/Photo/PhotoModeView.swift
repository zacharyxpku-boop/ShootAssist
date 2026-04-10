import SwiftUI
import PhotosUI
import StoreKit

struct PhotoModeView: View {
    /// 从首页英雄区直接进入时传 true，自动选中拍同款并打开图片选择器
    var launchCloneDirectly: Bool = false

    @StateObject private var cameraVM = CameraViewModel()
    @StateObject private var photoVM = PhotoModeViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var subManager: SubscriptionManager
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var shareButtonVisible = false
    @State private var showComparisonShare = false   // 对比拼图分享面板
    @State private var comparisonImage: UIImage? = nil
    @State private var showPoseGuide = false         // Pose 引导面板
    @State private var activePose: PoseData? = nil   // 当前选中的 Pose 引导

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部导航栏
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("返回")
                    Spacer()
                    Text("照片模式")
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Spacer()
                    Button(action: { showPoseGuide = true }) {
                        Image(systemName: "figure.arms.open")
                            .font(.system(size: 16)).foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Pose 引导")
                    Button(action: { cameraVM.toggleFlash() }) {
                        Image(systemName: cameraVM.flashIcon)
                            .font(.system(size: 18)).foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("闪光灯")
                    .accessibilityValue(cameraVM.flashMode == .off ? "关闭" : cameraVM.flashMode == .on ? "开启" : "自动")
                    .accessibilityHint("连续点击切换闪光灯模式")
                }
                .padding(.horizontal, 8).background(Color.black)

                // MARK: - 模式切换 Tab + 拍同款换图按钮
                HStack(spacing: 8) {
                    PhotoSubModeTab(selected: $photoVM.currentSubMode)

                    // 拍摄阶段显示"← 换图"返回设置
                    if photoVM.currentSubMode == .influencerClone && photoVM.isShootingPhase {
                        Button(action: { photoVM.clearReference() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left")
                                    .font(.system(size: 10, weight: .medium))
                                Text("换图")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, 8).padding(.horizontal, 8)
                .background(Color.black)
                .animation(.easeInOut(duration: 0.2), value: photoVM.currentSubMode)

                // MARK: - 相机预览 + 辅助叠加层
                ZStack {
                    CameraPreviewView(session: cameraVM.session)
                        .opacity(photoVM.currentSubMode == .influencerClone && !photoVM.isShootingPhase ? 0.4 : 1)

                    // Pose 引导悬浮卡（选中 Pose 后显示在左上角）
                    if let pose = activePose {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: pose.icon)
                                    .font(.system(size: 16))
                                    .foregroundColor(.rosePink)
                                Text(pose.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                                Spacer()
                                Button(action: { activePose = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white.opacity(0.7))
                                        .font(.system(size: 16))
                                }
                            }
                            Text(pose.description)
                                .font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.85))
                            ForEach(pose.tips.prefix(2), id: \.self) { tip in
                                Text("· \(tip)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            Text("📐 \(pose.cameraAngle)")
                                .font(.system(size: 10))
                                .foregroundColor(.rosePink.opacity(0.9))
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.6)))
                        .padding(.top, 8).padding(.leading, 8)
                        .frame(maxWidth: 200, maxHeight: .infinity, alignment: .topLeading)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .animation(.easeInOut(duration: 0.25), value: activePose?.id)
                    }

                    // 辅助叠加层（Vision AI 驱动 + 骨骼线 + Pose 匹配）
                    PhotoOverlayView(
                        subMode: photoVM.currentSubMode,
                        isShootingPhase: photoVM.isShootingPhase,
                        advice: photoVM.compositionAdvice,
                        isPersonDetected: photoVM.isPersonDetected,
                        showSafetyWarning: photoVM.showSafetyWarning,
                        safetyWarningText: photoVM.safetyWarningText,
                        guideTips: photoVM.dynamicGuideTips,
                        liveJoints: photoVM.liveJoints,
                        liveJointSources: photoVM.liveJointSources,
                        referenceJoints: photoVM.referenceJoints,
                        referenceJointSources: photoVM.referenceJointSources,
                        isReferenceAnalyzed: photoVM.isReferenceAnalyzed,
                        referenceCompleteness: photoVM.referenceCompleteness,
                        referenceReliabilityNote: photoVM.referenceReliabilityNote,
                        lightingResult: photoVM.lightingResult,
                        angleCoachingTips: photoVM.angleCoachingTips,
                        poseMatchScore: photoVM.poseMatchResult.score
                    )

                    // 拍同款设置阶段遮罩
                    if photoVM.currentSubMode == .influencerClone && !photoVM.isShootingPhase {
                        InfluencerSetupOverlay(
                            referenceImage: photoVM.referenceImage,
                            isAnalyzing: photoVM.isAnalyzingReference,
                            isAnalyzed: photoVM.isReferenceAnalyzed,
                            analysisError: photoVM.referenceAnalysisError,
                            freeUsesRemaining: photoVM.freeUsesRemaining,
                            isPro: subManager.isPro,
                            onPickImage: { photoVM.showImagePicker = true },
                            onStart: {
                                // 次数检查
                                if photoVM.isFreeLimitReached(isPro: subManager.isPro) {
                                    Analytics.track(Analytics.Event.freeLimitReached)
                                    showPaywall = true
                                    return
                                }
                                photoVM.recordCloneUse()
                                Analytics.track(Analytics.Event.cloneSessionStarted)
                                withAnimation(.easeInOut(duration: 0.3)) { photoVM.isShootingPhase = true }
                            }
                        )
                    }

                    // 低光 / 长时间未检测到人物提示
                    if cameraVM.visionService.isLowLightWarning && photoVM.currentSubMode != .influencerClone {
                        LowLightHint()
                            .transition(.opacity)
                    }

                    // 快门闪光
                    if cameraVM.showFlash {
                        Color.white.opacity(0.85).ignoresSafeArea().transition(.opacity)
                    }
                }
                // ✅ 锁定 3:4 宽高比，与苹果原相机照片模式完全一致
                // 传感器原始输出为横向 4:3，竖屏 portrait 下为 3:4（宽:高）
                // 加约束后 .resizeAspectFill 刚好填满容器，零裁剪零畸变
                .aspectRatio(3/4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 2)


                // MARK: - 底部操作栏
                HStack {
                    // 连拍按钮（长按快门也可触发，这里提供独立入口）
                    Button(action: { cameraVM.captureBurst(count: 5) }) {
                        VStack(spacing: 2) {
                            Image(systemName: "camera.on.rectangle")
                                .font(.system(size: 14)).foregroundColor(.white.opacity(0.8))
                            Text("×5").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.15)))
                    }
                    .accessibilityLabel("连拍")
                    .accessibilityHint("快速连续拍摄5张")
                    Spacer()
                    // 快门：短按单拍，长按（>0.5s）连拍5张
                    ShutterButton(
                        singleAction: { cameraVM.capturePhoto() },
                        burstAction: { cameraVM.captureBurst(count: 5) }
                    )
                    Spacer()
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) { cameraVM.switchCamera() }
                    }) {
                        Circle().fill(Color.white.opacity(0.15)).frame(width: 34, height: 34)
                            .overlay(Image(systemName: "camera.rotate").foregroundColor(.white).font(.system(size: 14)))
                    }
                    .accessibilityLabel("切换摄像头")
                    .accessibilityValue(cameraVM.isFrontCamera ? "前置" : "后置")
                }
                .padding(.horizontal, 30).padding(.vertical, 16).background(Color.black)
            }
        }
        // 分享悬浮按钮（保存成功后出现，6s 后淡出）
        .overlay(alignment: .bottom) {
            if shareButtonVisible, let img = cameraVM.lastSavedImage {
                Button(action: { showShareSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .semibold))
                        Text("分享这张")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .shadow(color: Color(hex: "FF5A7E").opacity(0.35), radius: 10, y: 4)
                    )
                }
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .sheet(isPresented: $showShareSheet) {
                    ShareSheet(items: [img, ReferralManager.shareAppendText()],
                               onDismiss: { shareButtonVisible = false },
                               onComplete: { ReferralManager.recordShareAction() })
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toast(isShowing: $cameraVM.showToast)
        .errorToast(isShowing: $cameraVM.showSaveError, message: cameraVM.saveErrorMessage)
        .onAppear {
            cameraVM.isVideoMode = false
            cameraVM.enableVisionAnalysis = true
            cameraVM.checkPermission()
            photoVM.bindVision(cameraVM.visionService)
            // 从首页英雄区直通：自动选中拍同款并弹出图片选择器
            if launchCloneDirectly {
                photoVM.currentSubMode = .influencerClone
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    photoVM.showImagePicker = true
                }
            }
        }
        .onDisappear { cameraVM.stopSession() }
        .overlay {
            if cameraVM.permissionDenied { PermissionDeniedView() }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .sheet(isPresented: $showPoseGuide) {
            PoseGuideSheet(activePose: $activePose, isPresented: $showPoseGuide)
        }
        // 对比拼图分享面板
        .sheet(isPresented: $showComparisonShare) {
            if let card = comparisonImage {
                ComparisonShareSheet(image: card, onDismiss: { showComparisonShare = false })
            }
        }
        // 参考图选择器
        .sheet(isPresented: $photoVM.showImagePicker) {
            ImagePickerView(image: $photoVM.referenceImage)
        }
        // 参考图选择后 → 重置为设置阶段 + 自动触发 Pose 分析
        .onChange(of: photoVM.referenceImageVersion) { _ in
            if photoVM.referenceImage != nil {
                photoVM.isShootingPhase = false
                photoVM.analyzeReferenceImage(cameraVM.visionService)
            } else {
                photoVM.clearReference()
            }
        }
        // 评分请求：累计第 3 张和第 10 张照片保存后各触发一次
        .onChange(of: cameraVM.totalPhotosSaved) { count in
            if count == 3 || count == 10 { requestAppReview() }
        }
        // 保存成功 → 拍同款模式生成对比拼图；普通模式显示分享按钮
        .onChange(of: cameraVM.lastSavedImage) { img in
            guard let captured = img else { return }

            if photoVM.currentSubMode == .influencerClone,
               photoVM.isShootingPhase,
               let refImage = photoVM.referenceImage {
                // 生成对比拼图（后台合成，主线程展示）
                let score = Int(photoVM.poseMatchResult.score * 100)
                DispatchQueue.global(qos: .userInitiated).async {
                    let card = ComparisonCardService.shared.generate(
                        reference: refImage,
                        captured: captured,
                        score: score
                    )
                    DispatchQueue.main.async {
                        comparisonImage = card
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            showComparisonShare = true
                        }
                    }
                }
            } else {
                // 普通模式：浮动分享按钮
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { shareButtonVisible = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    withAnimation(.easeOut(duration: 0.5)) { shareButtonVisible = false }
                }
            }
        }
    }

    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}

// MARK: - 子模式 Tab
private struct PhotoSubModeTab: View {
    @Binding var selected: PhotoSubMode
    var body: some View {
        HStack(spacing: 4) {
            ForEach(PhotoSubMode.allCases) { mode in
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selected = mode } }) {
                    Text(mode.rawValue)
                        .font(.system(size: 12, weight: selected == mode ? .semibold : .regular))
                        .foregroundColor(selected == mode ? .white : .white.opacity(0.5))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Group {
                            if selected == mode {
                                Capsule().fill(LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing))
                                    .shadow(color: .rosePink.opacity(0.3), radius: 4, y: 2)
                            }
                        })
                }
            }
        }
        .padding(3).background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

// MARK: - 快门按钮（短按单拍，长按 0.5s 连拍）
private struct ShutterButton: View {
    let singleAction: () -> Void
    let burstAction: () -> Void

    @State private var isPressed = false
    @State private var burstTimer: Timer?
    @State private var didBurst = false

    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 56, height: 56)
                .shadow(color: .rosePink.opacity(0.25), radius: 12)
            Circle()
                .fill(LinearGradient(colors: [.sakuraPink, .rosePink], startPoint: .top, endPoint: .bottom))
                .frame(width: isPressed ? 40 : 48, height: isPressed ? 40 : 48)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .accessibilityLabel("快门")
        .accessibilityHint("点击拍照，长按0.5秒连拍5张")
        .accessibilityAddTraits(.isButton)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    didBurst = false
                    burstTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                        burstAction()
                        didBurst = true
                    }
                }
                .onEnded { _ in
                    burstTimer?.invalidate(); burstTimer = nil
                    isPressed = false
                    if !didBurst { singleAction() }
                }
        )
    }
}

// MARK: - 权限被拒绝
private struct PermissionDeniedView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.rosePink)
            Text("需要相机权限").font(.system(size: 18, weight: .semibold)).foregroundColor(.berryBrown)
            Text("请在「设置」中开启相机权限\n才能使用拍摄功能")
                .font(.system(size: 13)).foregroundColor(.midBerryBrown).multilineTextAlignment(.center)
            Button(action: {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }) {
                Text("前往设置").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 24).padding(.vertical, 10)
                    .background(Capsule().fill(LinearGradient(colors: [.rosePink, .deepRose], startPoint: .leading, endPoint: .trailing)))
            }
        }
        .padding(40)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white).shadow(color: .rosePink.opacity(0.15), radius: 20, y: 8))
    }
}

// MARK: - 拍同款设置阶段遮罩

private struct InfluencerSetupOverlay: View {
    let referenceImage: UIImage?
    let isAnalyzing: Bool
    let isAnalyzed: Bool
    let analysisError: String?
    let freeUsesRemaining: Int
    let isPro: Bool
    let onPickImage: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // 参考图预览 or 上传提示
            if let img = referenceImage {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(width: 120, height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.rosePink.opacity(0.6), lineWidth: 1.5))

                    if isAnalyzing {
                        ProgressView()
                            .tint(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .offset(x: 6, y: 6)
                    } else if isAnalyzed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                            .offset(x: 6, y: 6)
                    }
                }

                VStack(spacing: 4) {
                    if isAnalyzing {
                        Text("正在提取轮廓…").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                    } else if isAnalyzed {
                        Text("轮廓提取完成 ✓").font(.system(size: 13)).foregroundColor(.green.opacity(0.9))
                    } else if let err = analysisError {
                        // 修复 bug：分析失败时明确展示错误，不再 spinner 永转
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11)).foregroundColor(.honeyOrange)
                            Text(err).font(.system(size: 12)).foregroundColor(.honeyOrange)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.5)))
                    }
                }
            } else {
                // 未选图状态
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.rosePink.opacity(0.15))
                            .frame(width: 80, height: 80)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 32))
                            .foregroundColor(.rosePink.opacity(0.8))
                    }
                    Text("先选一张参考图")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("AI 会自动提取人物轮廓\n让被拍者对齐站好再拍")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
            }

            // 按钮区
            VStack(spacing: 10) {
                Button(action: onPickImage) {
                    HStack(spacing: 6) {
                        Image(systemName: referenceImage == nil ? "photo.on.rectangle" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 13))
                        Text(referenceImage == nil ? "从相册选图" : "重新选图")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                }

                if isAnalyzed {
                    // 剩余次数提示（非 Pro 用户）
                    if !isPro {
                        HStack(spacing: 4) {
                            Image(systemName: freeUsesRemaining > 0 ? "checkmark.circle" : "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(freeUsesRemaining > 0 ? .white.opacity(0.7) : .honeyOrange)
                            Text(freeUsesRemaining > 0
                                 ? "今天还剩 \(freeUsesRemaining) 次免费拍同款"
                                 : "今日免费次数已用完 · 升级 Pro 无限拍")
                                .font(.system(size: 11))
                                .foregroundColor(freeUsesRemaining > 0 ? .white.opacity(0.6) : .honeyOrange)
                        }
                        .transition(.opacity)
                    }

                    Button(action: onStart) {
                        HStack(spacing: 6) {
                            if !isPro && freeUsesRemaining <= 0 {
                                Image(systemName: "crown.fill").font(.system(size: 12))
                                Text("升级 Pro · 开始拍摄").font(.system(size: 15, weight: .semibold))
                            } else {
                                Text("开始拍摄 →").font(.system(size: 15, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: !isPro && freeUsesRemaining <= 0
                                    ? [Color(hex: "FF8C42"), Color(hex: "FF5A7E")]
                                    : [.rosePink, .peachPink],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .shadow(color: .rosePink.opacity(0.35), radius: 8, y: 3)
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .padding(.horizontal, 32)
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isAnalyzed)

            Spacer()
        }
        .background(Color.black.opacity(0.55))
    }
}

// MARK: - 系统相册图片选择器
struct ImagePickerView: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images; config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView
        init(_ parent: ImagePickerView) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [weak self] image, _ in
                DispatchQueue.main.async { self?.parent.image = image as? UIImage }
            }
        }
    }
}

// MARK: - 对比拼图分享面板

private struct ComparisonShareSheet: View {
    let image: UIImage
    let onDismiss: () -> Void
    @State private var showSystemShare = false

    var body: some View {
        VStack(spacing: 0) {
            // 拖动指示器
            Capsule().fill(Color.gray.opacity(0.3)).frame(width: 40, height: 4).padding(.top, 12)

            // 标题
            VStack(spacing: 4) {
                Text("同款对比图生成了 🎉").font(.system(size: 17, weight: .semibold)).foregroundColor(.berryBrown)
                Text("发出去让朋友也来挑战一下？").font(.system(size: 12)).foregroundColor(.midBerryBrown)
            }
            .padding(.top, 16).padding(.bottom, 16)

            // 对比图预览
            Image(uiImage: image)
                .resizable().scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

            // 操作按钮
            HStack(spacing: 12) {
                // 分享
                Button(action: { showSystemShare = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14))
                        Text("分享到小红书/朋友圈").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(
                        Capsule().fill(LinearGradient(
                            colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .shadow(color: Color(hex: "FF5A7E").opacity(0.3), radius: 8, y: 3)
                    )
                }

                // 关闭
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundColor(.midBerryBrown)
                        .frame(width: 46, height: 46).background(Circle().fill(Color.gray.opacity(0.1)))
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 36)
        }
        .background(Color(hex: "FAFAF9").ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .sheet(isPresented: $showSystemShare) {
            ShareSheet(
                items: [image, ReferralManager.shareAppendText()],
                onDismiss: { showSystemShare = false; onDismiss() },
                onComplete: {
                    ReferralManager.recordShareAction()
                    Analytics.track(Analytics.Event.comparisonCardShared)
                    Analytics.track(Analytics.Event.referralGenerated)
                }
            )
        }
    }
}

// MARK: - 低光 / 持续无人物提示

private struct LowLightHint: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "sun.min").font(.system(size: 13)).foregroundColor(.honeyOrange)
                Text("检测不到人物，试试光线更亮的地方")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.black.opacity(0.6)))
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Pose 引导面板（相机内浏览 + 一键选中）

private struct PoseGuideSheet: View {
    @Binding var activePose: PoseData?
    @Binding var isPresented: Bool
    @State private var selectedCategory: PoseCategory? = poseDatabase.first

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分类横向滚动
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(poseDatabase) { cat in
                            Button(action: { selectedCategory = cat }) {
                                HStack(spacing: 4) {
                                    Text(cat.icon).font(.system(size: 14))
                                    Text(cat.name).font(.system(size: 13, weight: .medium))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(
                                    Capsule().fill(selectedCategory?.id == cat.id
                                        ? Color.rosePink : Color.rosePink.opacity(0.12))
                                )
                                .foregroundColor(selectedCategory?.id == cat.id ? .white : .berryBrown)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }

                Divider()

                // Pose 列表
                if let category = selectedCategory {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(category.poses) { pose in
                                Button(action: {
                                    activePose = pose
                                    isPresented = false
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: pose.icon)
                                            .font(.system(size: 22))
                                            .foregroundColor(.rosePink)
                                            .frame(width: 44, height: 44)
                                            .background(Circle().fill(Color.rosePink.opacity(0.1)))

                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(pose.name)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundColor(.berryBrown)
                                                Spacer()
                                                Text(String(repeating: "★", count: pose.difficulty))
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.honeyOrange)
                                            }
                                            Text(pose.description)
                                                .font(.system(size: 12))
                                                .foregroundColor(.midBerryBrown)
                                                .lineLimit(1)
                                            Text("📐 \(pose.cameraAngle) · 适合\(pose.bestFor)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.midBerryBrown.opacity(0.7))
                                                .lineLimit(1)
                                        }

                                        Image(systemName: "camera.viewfinder")
                                            .font(.system(size: 14))
                                            .foregroundColor(.rosePink.opacity(0.6))
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.warmCream))
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Pose 引导")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { isPresented = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    if activePose != nil {
                        Button("清除引导") { activePose = nil; isPresented = false }
                            .foregroundColor(.midBerryBrown)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI
import PhotosUI
import Vision
import Combine

class PhotoModeViewModel: ObservableObject {
    @Published var currentSubMode: PhotoSubMode = .influencerClone

    // MARK: - Vision 驱动的实时状态
    @Published var compositionAdvice: CompositionAdvice = .empty
    @Published var isPersonDetected = false
    @Published var showSafetyWarning = false
    @Published var safetyWarningText = ""

    // MARK: - 实时骨骼关键点（来自 VisionService）
    @Published var liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]

    // MARK: - 拍同款：参考图 + Pose 分析
    @Published var referenceImage: UIImage? {
        didSet { referenceImageVersion += 1 }  // 修复 #14：UIImage 不是 Equatable，用 version 触发 onChange
    }
    @Published var referenceImageVersion: Int = 0
    @Published var showImagePicker = false
    @Published var isShootingPhase: Bool = false   // false=设置阶段, true=拍摄阶段
    @Published var referenceJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var poseMatchResult: PoseMatchResult = .empty
    @Published var isReferenceAnalyzed = false
    @Published var isAnalyzingReference = false     // 分析中（用于 UI spinner）
    @Published var referenceAnalysisError: String? = nil  // 分析失败的原因

    // MARK: - 服务
    private let poseMatchingService = PoseMatchingService()
    private var cancellables = Set<AnyCancellable>()

    /// 绑定 CameraViewModel 内的 VisionService（修复 #13：全部用 sink + cancellables，避免 assign(to:) 无法取消）
    func bindVision(_ visionService: VisionService) {
        cancellables.removeAll()

        // 构图建议
        visionService.$compositionAdvice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] advice in self?.compositionAdvice = advice }
            .store(in: &cancellables)

        // 人体检测
        visionService.$isPersonDetected
            .receive(on: DispatchQueue.main)
            .sink { [weak self] detected in self?.isPersonDetected = detected }
            .store(in: &cancellables)

        // 实时骨骼关键点
        visionService.$bodyJoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] joints in
                guard let self else { return }
                self.liveJoints = joints
                // 如果有参考图骨骼，执行实时匹配
                if !self.referenceJoints.isEmpty && !joints.isEmpty {
                    self.poseMatchResult = self.poseMatchingService.comparePoses(
                        reference: self.referenceJoints,
                        current: joints
                    )
                }
            }
            .store(in: &cancellables)

        // 安全警告
        visionService.$compositionAdvice
            .receive(on: DispatchQueue.main)
            .sink { [weak self] advice in
                guard let self else { return }
                if advice.isCutOff {
                    self.showSafetyWarning = true
                    self.safetyWarningText = advice.tips.first(where: { $0.contains("⚠️") }) ?? "注意构图"
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                        self?.showSafetyWarning = false
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 分析参考图的 Pose（导入参考图后调用）
    func analyzeReferenceImage(_ visionService: VisionService) {
        guard let uiImage = referenceImage, let cgImage = uiImage.cgImage else {
            referenceJoints = [:]
            isReferenceAnalyzed = false
            isAnalyzingReference = false
            return
        }

        isAnalyzingReference = true
        referenceAnalysisError = nil

        // 在后台线程分析
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let joints = visionService.analyzePose(in: cgImage) ?? [:]
            DispatchQueue.main.async {
                self.isAnalyzingReference = false
                self.referenceJoints = joints
                self.isReferenceAnalyzed = !joints.isEmpty
                if joints.isEmpty {
                    // 修复 bug：分析失败时明确设置 error，不再让 spinner 永转
                    self.referenceAnalysisError = "未检测到人物姿势，换一张试试"
                    self.poseMatchResult = PoseMatchResult(
                        score: 0, matchedJoints: 0, totalJoints: 0,
                        tips: [
                            "参考图中未检测到人物姿势",
                            "试试选一张人物清晰、全身可见的照片",
                            "避免选修图过重或人体被大面积遮挡的图"
                        ],
                        isMatched: false, perJointMatch: [:]
                    )
                }
            }
        }
    }

    // MARK: - 清除参考图（回到设置阶段）
    func clearReference() {
        referenceImage = nil
        referenceJoints = [:]
        isReferenceAnalyzed = false
        isAnalyzingReference = false
        referenceAnalysisError = nil
        poseMatchResult = .empty
        isShootingPhase = false
    }

    // MARK: - 机位提示（Vision 驱动的动态提示）
    var dynamicGuideTips: [String] {
        if !isPersonDetected {
            return ["对准人物", "等待检测..."]
        }
        var tips = compositionAdvice.tips.filter { !$0.contains("⚠️") }
        if tips.isEmpty {
            tips = ["构图很棒 ✦", "按快门吧"]
        }
        return tips
    }

    deinit {
        cancellables.removeAll()
    }
}

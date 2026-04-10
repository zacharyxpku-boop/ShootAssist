import SwiftUI
import PhotosUI
import Vision
import Combine

class PhotoModeViewModel: ObservableObject {
    @Published var currentSubMode: PhotoSubMode = .influencerClone

    // MARK: - 每日免费次数（内测阶段 100 次/天，后续 Pro 无限）
    static let freeDailyLimit = 100
    @AppStorage("sa_clone_date")  private var storedDate: String = ""
    @AppStorage("sa_clone_count") private var storedCount: Int = 0

    /// 今日剩余免费次数（非 Pro 时有意义）
    var freeUsesRemaining: Int {
        let today = Self.todayString()
        if storedDate != today { return Self.freeDailyLimit }
        return max(0, Self.freeDailyLimit - storedCount)
    }

    /// 记录一次使用（开始拍摄时调用）
    func recordCloneUse() {
        let today = Self.todayString()
        if storedDate != today { storedDate = today; storedCount = 0 }
        storedCount += 1
    }

    /// 是否已达免费上限
    func isFreeLimitReached(isPro: Bool) -> Bool {
        guard !isPro else { return false }
        return freeUsesRemaining <= 0
    }

    private static func todayString() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    // MARK: - Vision 驱动的实时状态
    @Published var compositionAdvice: CompositionAdvice = .empty
    @Published var isPersonDetected = false
    @Published var showSafetyWarning = false
    @Published var safetyWarningText = ""

    // MARK: - 实时骨骼关键点（来自 VisionService）
    @Published var liveJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var liveJointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]

    // MARK: - 拍同款：参考图 + Pose 分析
    @Published var referenceImage: UIImage? {
        didSet { referenceImageVersion += 1 }  // 修复 #14：UIImage 不是 Equatable，用 version 触发 onChange
    }
    @Published var referenceImageVersion: Int = 0
    @Published var showImagePicker = false
    @Published var isShootingPhase: Bool = false   // false=设置阶段, true=拍摄阶段
    @Published var referenceJoints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
    @Published var referenceJointSources: [VNHumanBodyPoseObservation.JointName: JointSource] = [:]
    @Published var poseMatchResult: PoseMatchResult = .empty
    @Published var isReferenceAnalyzed = false
    @Published var isAnalyzingReference = false     // 分析中（用于 UI spinner）
    @Published var referenceAnalysisError: String? = nil  // 分析失败的原因
    @Published var referenceCompleteness: Float = 0
    @Published var referenceReliabilityNote: String? = nil

    // MARK: - 新增：角度coaching + 光线检测 + 难度进阶
    @Published var angleCoachingTips: [String] = []
    @Published var lightingResult: LightingResult = .empty
    let progressionService = PoseProgressionService()

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

        // 光线检测结果
        visionService.$lightingResult
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in self?.lightingResult = result }
            .store(in: &cancellables)

        // Completed pose (includes joint sources and metadata)
        visionService.$completedPose
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completedPose in
                guard let self else { return }
                if let pose = completedPose {
                    self.liveJoints = pose.joints
                    self.liveJointSources = pose.jointSources
                    // If we have both live joints and reference joints, recompute match
                    if !self.referenceJoints.isEmpty && !pose.joints.isEmpty {
                        self.poseMatchResult = self.poseMatchingService.comparePoses(
                            reference: self.referenceJoints,
                            refSources: self.referenceJointSources,
                            current: pose.joints,
                            curSources: pose.jointSources
                        )
                        // 角度 coaching：只在匹配分数中等时提供（太低=姿势完全不对，太高=已经够好）
                        if self.poseMatchResult.score > 0.3 && self.poseMatchResult.score < 0.85 {
                            let coaching = self.poseMatchingService.angleCoaching(
                                reference: self.referenceJoints,
                                current: pose.joints
                            )
                            self.angleCoachingTips = coaching.prefix(2).map { $0.tip }
                        } else {
                            self.angleCoachingTips = []
                        }

                        // 匹配成功 → 记录进阶
                        if self.poseMatchResult.isMatched {
                            // 用 referenceImage 对应的 poseName (如果有)
                            self.progressionService.recordCompletion(
                                poseName: "clone_\(self.referenceImageVersion)",
                                matchScore: self.poseMatchResult.score
                            )
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - 分析参考图的 Pose（导入参考图后调用）
    func analyzeReferenceImage(_ visionService: VisionService) {
        guard let uiImage = referenceImage else {
            referenceJoints = [:]
            referenceJointSources = [:]
            referenceCompleteness = 0
            referenceReliabilityNote = nil
            isReferenceAnalyzed = false
            isAnalyzingReference = false
            return
        }

        isAnalyzingReference = true
        referenceAnalysisError = nil

        // In background thread analyze
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let completedPose = visionService.analyzePose(in: uiImage)
            DispatchQueue.main.async {
                self.isAnalyzingReference = false
                let pose = completedPose
                self.referenceJoints = pose.joints
                self.referenceJointSources = pose.jointSources
                self.referenceCompleteness = pose.completenessScore
                self.referenceReliabilityNote = pose.reliabilityNote
                self.isReferenceAnalyzed = pose.canUseForMatching
                if !pose.canUseForMatching {
                    if !pose.joints.isEmpty {
                        self.referenceAnalysisError = pose.reliabilityNote ?? "参考图姿态不够清晰"
                    } else {
                        self.referenceAnalysisError = "未检测到人物姿势，换一张试试"
                    }
                    self.poseMatchResult = PoseMatchResult(
                        score: 0, matchedJoints: 0, totalJoints: 0,
                        tips: [
                            "参考图中未检测到人物姿势",
                            "试试选一张人物清晰、全身可见的照片",
                            "避免选修图过重或人体被大面积遮挡的图"
                        ],
                        isMatched: false, perJointMatch: [:],
                        canMatch: false,
                        coverageNote: nil
                    )
                } else {
                    self.referenceAnalysisError = nil
                }
            }
        }
    }

    // MARK: - 清除参考图（回到设置阶段）
    func clearReference() {
        referenceImage = nil
        referenceJoints = [:]
        referenceJointSources = [:]
        referenceCompleteness = 0
        referenceReliabilityNote = nil
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

    // MARK: - Computed property for reference completeness label
    var referenceCompletenessLabel: String {
        if referenceCompleteness >= 0.8 {
            return "参考图姿态完整"
        } else if referenceCompleteness >= 0.5 {
            return "参考图姿态基本可用"
        } else if referenceCompleteness >= 0.35 {
            return "参考图姿态较残缺，补全仅供参考"
        } else {
            return "参考图无法用于匹配"
        }
    }

    deinit {
        cancellables.removeAll()
    }
}

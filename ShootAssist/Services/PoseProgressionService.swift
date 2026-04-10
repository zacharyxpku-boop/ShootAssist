import Foundation

// MARK: - 姿势进阶管理（难度解锁 + 成就追踪）
class PoseProgressionService: ObservableObject {

    private let defaults = UserDefaults.standard
    private let completedKey = "completedPoses"
    private let streakKey = "poseStreak"
    private let lastDateKey = "lastPracticeDate"

    /// 已完成的 pose 名称集合
    @Published var completedPoseNames: Set<String> = []
    /// 当前连续练习天数
    @Published var streak: Int = 0
    /// 当前解锁的最高难度
    @Published var unlockedDifficulty: Int = 1

    init() {
        loadState()
    }

    // MARK: - 记录一次成功匹配
    func recordCompletion(poseName: String, matchScore: Float) {
        guard matchScore >= 0.65 else { return }

        completedPoseNames.insert(poseName)
        defaults.set(Array(completedPoseNames), forKey: completedKey)

        updateStreak()
        recalculateUnlockedDifficulty()
    }

    // MARK: - 获取推荐的下一个 pose
    func nextRecommendedPose(from poses: [PoseData]) -> PoseData? {
        // 优先推荐未完成的、当前难度范围内的
        let available = poses.filter {
            $0.difficulty <= unlockedDifficulty && !completedPoseNames.contains($0.name)
        }
        if let next = available.first { return next }

        // 全做完了，推一个高一级的作为"挑战"
        let challenge = poses.first { $0.difficulty == unlockedDifficulty + 1 }
        return challenge ?? poses.randomElement()
    }

    // MARK: - 统计
    var completedCount: Int { completedPoseNames.count }

    func completionRate(for category: PoseCategory) -> Float {
        let total = category.poses.count
        guard total > 0 else { return 0 }
        let done = category.poses.filter { completedPoseNames.contains($0.name) }.count
        return Float(done) / Float(total)
    }

    // MARK: - Private

    private func loadState() {
        if let saved = defaults.stringArray(forKey: completedKey) {
            completedPoseNames = Set(saved)
        }
        streak = defaults.integer(forKey: streakKey)
        recalculateUnlockedDifficulty()
    }

    private func updateStreak() {
        let today = Calendar.current.startOfDay(for: Date())
        if let lastDate = defaults.object(forKey: lastDateKey) as? Date {
            let lastDay = Calendar.current.startOfDay(for: lastDate)
            let diff = Calendar.current.dateComponents([.day], from: lastDay, to: today).day ?? 0
            if diff == 1 {
                streak += 1
            } else if diff > 1 {
                streak = 1 // 断了，重新计
            }
            // diff == 0 → 同一天，不变
        } else {
            streak = 1
        }
        defaults.set(streak, forKey: streakKey)
        defaults.set(today, forKey: lastDateKey)
    }

    private func recalculateUnlockedDifficulty() {
        // 规则：完成 5 个 difficulty=1 的 → 解锁 2；完成 5 个 difficulty=2 → 解锁 3
        let allPoses = poseDatabase.flatMap { $0.poses }
        let d1Done = allPoses.filter { $0.difficulty == 1 && completedPoseNames.contains($0.name) }.count
        let d2Done = allPoses.filter { $0.difficulty == 2 && completedPoseNames.contains($0.name) }.count

        if d2Done >= 5 {
            unlockedDifficulty = 3
        } else if d1Done >= 5 {
            unlockedDifficulty = 2
        } else {
            unlockedDifficulty = 1
        }
    }
}

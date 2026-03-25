import AVFoundation
import Vision
import UIKit
import CoreMedia

// MARK: - 分析结果模型

struct EmojiMove: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let emoji: String
    let description: String
}

struct AnalyzedTemplate {
    let audioURL: URL?
    let emojiMoves: [EmojiMove]
    let duration: TimeInterval
}

// MARK: - 视频分析服务
// 用法：await VideoAnalysisService.shared.analyzeVideo(asset:onProgress:)

class VideoAnalysisService {
    static let shared = VideoAnalysisService()
    private init() {}

    /// 完整分析一个视频 asset
    /// - Parameters:
    ///   - asset: PHPickerViewController 选出的视频 AVAsset
    ///   - sampleInterval: 采样间隔（秒），默认 0.2s = 5fps
    ///   - onProgress: 0.0~1.0 进度回调（主线程）
    func analyzeVideo(
        asset: AVAsset,
        sampleInterval: TimeInterval = 0.2,
        onProgress: @escaping (Double) -> Void
    ) async -> AnalyzedTemplate {

        // 并行：音频提取 & 视频帧姿势提取
        async let audioTask = extractAudio(from: asset)
        async let posesTask = extractPoseTimeline(from: asset, sampleInterval: sampleInterval, onProgress: onProgress)

        let (audioURL, poseFrames) = await (audioTask, posesTask)

        // 生成 emoji 时间轴
        let emojiMoves = generateEmojiTimeline(from: poseFrames)

        let duration: TimeInterval
        if let durationCM = try? await asset.load(.duration) {
            duration = CMTimeGetSeconds(durationCM)
        } else {
            duration = 0
        }

        await MainActor.run { onProgress(1.0) }

        return AnalyzedTemplate(
            audioURL: audioURL,
            emojiMoves: emojiMoves,
            duration: duration
        )
    }

    // MARK: - 提取音频 → 临时 .m4a

    private func extractAudio(from asset: AVAsset) async -> URL? {
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return nil }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_audio_\(Int(Date().timeIntervalSince1970)).m4a")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exportSession.status == .completed else { return nil }
        return outputURL
    }

    // MARK: - 逐帧提取姿势

    private func extractPoseTimeline(
        from asset: AVAsset,
        sampleInterval: TimeInterval,
        onProgress: @escaping (Double) -> Void
    ) async -> [(timestamp: TimeInterval, joints: [VNHumanBodyPoseObservation.JointName: CGPoint])] {

        guard let durationCM = try? await asset.load(.duration) else { return [] }
        let duration = CMTimeGetSeconds(durationCM)
        guard duration > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(seconds: sampleInterval * 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter  = CMTime(seconds: sampleInterval * 0.5, preferredTimescale: 600)

        var results: [(TimeInterval, [VNHumanBodyPoseObservation.JointName: CGPoint])] = []
        let totalSteps = Int(duration / sampleInterval) + 1
        var step = 0

        var currentTime: TimeInterval = 0
        while currentTime <= duration {
            let cmTime = CMTime(seconds: currentTime, preferredTimescale: 600)

            if let cgImage = try? generator.copyCGImage(at: cmTime, actualTime: nil) {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
                let req = VNDetectHumanBodyPoseRequest()
                try? handler.perform([req])
                if let obs = req.results?.first {
                    let joints = extractJoints(from: obs)
                    if !joints.isEmpty {
                        results.append((currentTime, joints))
                    }
                }
            }

            step += 1
            // 进度上限到 0.9，留 0.1 给 emoji 生成阶段
            let progress = min(Double(step) / Double(max(totalSteps, 1)) * 0.9, 0.9)
            await MainActor.run { onProgress(progress) }

            currentTime += sampleInterval
        }

        return results
    }

    // MARK: - 关键点提取

    private func extractJoints(
        from observation: VNHumanBodyPoseObservation
    ) -> [VNHumanBodyPoseObservation.JointName: CGPoint] {
        var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        let keys: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck,
            .leftShoulder, .rightShoulder,
            .leftElbow, .rightElbow,
            .leftWrist, .rightWrist,
            .leftHip, .rightHip
        ]
        for key in keys {
            if let pt = try? observation.recognizedPoint(key), pt.confidence > 0.3 {
                joints[key] = CGPoint(x: pt.location.x, y: pt.location.y)
            }
        }
        return joints
    }

    // MARK: - 关键点 → emoji 分类

    func classifyPose(
        joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    ) -> (emoji: String, description: String)? {
        guard let lw = joints[.leftWrist], let rw = joints[.rightWrist] else { return nil }
        let nose = joints[.nose]
        let neck = joints[.neck]
        let lh   = joints[.leftHip]
        let rh   = joints[.rightHip]

        // 双手举过头（欢呼/加油）
        if let n = nose, lw.y > n.y + 0.08 && rw.y > n.y + 0.08 {
            return ("🙌", "双手举高")
        }
        // 单手举高
        if let n = nose {
            if lw.y > n.y + 0.12 { return ("☝️", "指天") }
            if rw.y > n.y + 0.12 { return ("☝️", "指天") }
        }
        // 双手靠拢（比心 / 拍手）
        if abs(lw.x - rw.x) < 0.12 && abs(lw.y - rw.y) < 0.12 {
            if let n = nose, (lw.y + rw.y) / 2 > n.y - 0.05 {
                return ("🫶", "比心")
            }
            return ("👏", "拍手")
        }
        // 双手大开（展臂）
        if abs(lw.x - rw.x) > 0.45 {
            return ("🤸", "展开双臂")
        }
        // 飞吻（手贴近嘴）
        if let n = nose {
            if abs(lw.y - n.y) < 0.06 && abs(lw.x - n.x) < 0.12 { return ("😘", "飞吻") }
            if abs(rw.y - n.y) < 0.06 && abs(rw.x - n.x) < 0.12 { return ("😘", "飞吻") }
        }
        // 手在头部附近（捂脸/卖萌）
        if let n = nose {
            let lNear = abs(lw.y - n.y) < 0.1 && abs(lw.x - n.x) < 0.2
            let rNear = abs(rw.y - n.y) < 0.1 && abs(rw.x - n.x) < 0.2
            if lNear || rNear { return ("🤭", "捂脸卖萌") }
        }
        // 叉腰
        if let lHip = lh, let rHip = rh,
           abs(lw.y - lHip.y) < 0.1 && abs(rw.y - rHip.y) < 0.1 {
            return ("🤗", "叉腰")
        }
        // 双手交叉胸前
        if let nk = neck, lw.x > rw.x,
           abs(lw.y - nk.y) < 0.2 && abs(rw.y - nk.y) < 0.2 {
            return ("🙅", "双手交叉")
        }
        // 托腮（单手在下巴附近）
        if let nk = neck, let n = nose {
            let chinY = (nk.y + n.y) / 2
            if abs(lw.y - chinY) < 0.07 { return ("🤔", "托腮") }
            if abs(rw.y - chinY) < 0.07 { return ("🤔", "托腮") }
        }

        return nil  // 未识别到特定姿势
    }

    // MARK: - 生成 emoji 时间轴（稳定性去重）

    private func generateEmojiTimeline(
        from frames: [(timestamp: TimeInterval, joints: [VNHumanBodyPoseObservation.JointName: CGPoint])]
    ) -> [EmojiMove] {
        var moves: [EmojiMove] = []
        var lastEmoji = ""
        var candidateEmoji = ""
        var candidateDesc = ""
        var candidateTimestamp: TimeInterval = 0
        var stableCount = 0

        for frame in frames {
            if let classified = classifyPose(joints: frame.joints) {
                if classified.emoji == candidateEmoji {
                    stableCount += 1
                } else {
                    candidateEmoji = classified.emoji
                    candidateDesc = classified.description
                    candidateTimestamp = frame.timestamp
                    stableCount = 1
                }

                // 稳定 2 帧（0.4s）且与上一个不同，才发出新的 emoji
                if stableCount >= 2 && candidateEmoji != lastEmoji {
                    let minGap = moves.last.map { candidateTimestamp - $0.timestamp >= 0.5 } ?? true
                    if minGap {
                        moves.append(EmojiMove(
                            timestamp: candidateTimestamp,
                            emoji: candidateEmoji,
                            description: candidateDesc
                        ))
                        lastEmoji = candidateEmoji
                    }
                }
            } else {
                // 本帧无法识别，重置候选状态
                candidateEmoji = ""
                stableCount = 0
            }
        }

        return moves
    }
}

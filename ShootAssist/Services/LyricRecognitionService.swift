import Foundation
import Speech
import AVFoundation

// MARK: - 歌词识别服务（SFSpeechRecognizer，中文优先）

class LyricRecognitionService {
    static let shared = LyricRecognitionService()
    private init() {}

    /// 从音频文件 URL 识别歌词（最多处理前60秒）
    func recognizeLyrics(from url: URL) async -> [LyricLine] {
        // 申请权限
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { return [] }

        // 优先中文识别器
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
                      ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { return [] }

        // 超过60秒则截断，规避服务端限制
        let targetURL = await clipAudioIfNeeded(url: url, maxSeconds: 60) ?? url

        let request = SFSpeechURLRecognitionRequest(url: targetURL)
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { cont in
            // 用串行队列保护 resumed 标志，防止 speech callback 和 timeout 同时 resume
            let guard_q = DispatchQueue(label: "lyric.cont.guard")
            var resumed = false

            let task = recognizer.recognitionTask(with: request) { result, error in
                guard_q.sync {
                    guard !resumed else { return }
                    if let result, result.isFinal {
                        resumed = true
                        cont.resume(returning: Self.segmentsToLines(result.bestTranscription.segments))
                    } else if error != nil {
                        resumed = true
                        cont.resume(returning: [])
                    }
                }
            }

            // 90s 超时兜底
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                guard_q.sync {
                    guard !resumed else { return }
                    task.cancel()
                    resumed = true
                    cont.resume(returning: [])
                }
            }
        }
    }

    // MARK: - 截取前 N 秒

    private func clipAudioIfNeeded(url: URL, maxSeconds: TimeInterval) async -> URL? {
        let asset = AVURLAsset(url: url)
        guard let durationCM = try? await asset.load(.duration) else { return nil }
        let total = CMTimeGetSeconds(durationCM)
        guard total > maxSeconds else { return nil }

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else { return nil }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_lyric_clip_\(Int(Date().timeIntervalSince1970)).m4a")
        try? FileManager.default.removeItem(at: outURL)
        session.outputURL = outURL
        session.outputFileType = .m4a
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: maxSeconds, preferredTimescale: 600)
        )

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }
        return session.status == .completed ? outURL : nil
    }

    // MARK: - 分段 → 歌词行（每5个词一行）

    private static func segmentsToLines(_ segments: [SFTranscriptionSegment]) -> [LyricLine] {
        guard !segments.isEmpty else { return [] }
        var lines: [LyricLine] = []
        let chunkSize = 5
        var i = 0
        while i < segments.count {
            let chunk = Array(segments[i ..< min(i + chunkSize, segments.count)])
            guard let first = chunk.first, let last = chunk.last else { i += chunkSize; continue }
            let text  = chunk.map { $0.substring }.joined() + " ♪"
            let start = first.timestamp
            let end: TimeInterval = (i + chunkSize < segments.count)
                ? segments[i + chunkSize].timestamp
                : last.timestamp + last.duration + 0.8
            lines.append(LyricLine(text: text, startTime: start, endTime: end))
            i += chunkSize
        }
        return lines
    }
}

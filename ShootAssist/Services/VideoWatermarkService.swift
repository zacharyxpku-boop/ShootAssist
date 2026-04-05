import AVFoundation
import UIKit
import CoreImage

// MARK: - 视频水印合成服务
// 录制完成后调用，给视频加上"小白快门制作"水印，返回合成后的临时文件 URL

class VideoWatermarkService {
    static let shared = VideoWatermarkService()
    private init() {}

    /// 给视频添加文字水印
    /// - Parameters:
    ///   - inputURL: 原始视频 URL
    ///   - label: 水印文字（默认"小白快门制作"）
    ///   - completion: 成功返回合成后 URL，失败返回 nil
    func addWatermark(
        to inputURL: URL,
        label: String = "小白快门制作",
        completion: @escaping (URL?) -> Void
    ) {
        Task {
            do {
                let result = try await addWatermarkAsync(to: inputURL, label: label)
                await MainActor.run { completion(result) }
            } catch {
                await MainActor.run { completion(inputURL) }
            }
        }
    }

    private func addWatermarkAsync(to inputURL: URL, label: String) async throws -> URL {
        let asset = AVURLAsset(url: inputURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return inputURL }

        let naturalSize = try await videoTrack.load(.naturalSize)
            .applying(try await videoTrack.load(.preferredTransform))
        let videoSize = CGSize(width: abs(naturalSize.width), height: abs(naturalSize.height))
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)

        // MARK: 构建水印 CALayer
        let watermarkLayer = makeWatermarkLayer(text: label, videoSize: videoSize)

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: videoSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(watermarkLayer)

        // MARK: 合成
        let composition      = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()

        guard
            let compVideoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compAudioTrack = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return inputURL }

        let timeRange = CMTimeRange(start: .zero, duration: duration)

        try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        if let audioTrack = audioTracks.first {
            try compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        compVideoTrack.preferredTransform = preferredTransform

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        videoComposition.instructions      = [instruction]
        videoComposition.frameDuration     = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize        = videoSize
        videoComposition.animationTool     = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // MARK: 导出
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sa_wm_\(Int(Date().timeIntervalSince1970)).mov")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else { return inputURL }

        exportSession.outputURL          = outputURL
        exportSession.outputFileType     = .mov
        exportSession.videoComposition   = videoComposition
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()
        return exportSession.status == .completed ? outputURL : inputURL
    }

    // MARK: - 水印 CALayer

    private func makeWatermarkLayer(text: String, videoSize: CGSize) -> CALayer {
        let layer = CALayer()
        layer.frame = CGRect(origin: .zero, size: videoSize)

        // 底部右侧 badge 背景
        let badgeH: CGFloat = 28
        let badgeW: CGFloat = CGFloat(text.count) * 10 + 24
        let margin: CGFloat = 16
        let badgeRect = CGRect(
            x: videoSize.width - badgeW - margin,
            y: margin,                          // CoreAnimation 坐标系 Y 轴向上，bottom = small y
            width: badgeW,
            height: badgeH
        )

        let bgLayer = CALayer()
        bgLayer.frame = badgeRect
        bgLayer.backgroundColor = UIColor.black.withAlphaComponent(0.45).cgColor
        bgLayer.cornerRadius = badgeH / 2

        let textLayer = CATextLayer()
        textLayer.frame = badgeRect
        textLayer.string = text
        textLayer.font   = CTFontCreateWithName("PingFangSC-Medium" as CFString, 0, nil)
        textLayer.fontSize    = 12
        textLayer.foregroundColor = UIColor.white.withAlphaComponent(0.9).cgColor
        textLayer.alignmentMode   = .center
        textLayer.contentsScale   = UIScreen.main.scale

        layer.addSublayer(bgLayer)
        layer.addSublayer(textLayer)
        return layer
    }
}

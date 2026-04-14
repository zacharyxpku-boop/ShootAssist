import SwiftUI
import AVFoundation

/// 画中画参考视频小窗 — 悬浮在相机预览上层，循环播放参考视频
/// 录制时只显示在 UI 上，不录入最终视频
struct PiPVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    /// 每次值变化都会把视频 seek 到 0 + 重新播放（用于录制开始时从头同步）
    let restartToken: Int

    func makeUIView(context: Context) -> PiPPlayerUIView {
        let view = PiPPlayerUIView(url: url)
        context.coordinator.lastToken = restartToken
        return view
    }

    func updateUIView(_ uiView: PiPPlayerUIView, context: Context) {
        if restartToken != context.coordinator.lastToken {
            context.coordinator.lastToken = restartToken
            uiView.restartFromBeginning()
            return
        }
        if isPlaying {
            uiView.play()
        } else {
            uiView.pause()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var lastToken: Int = -1
    }
}

class PiPPlayerUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        layer.cornerRadius = 8
        clipsToBounds = true

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(items: [item])
        looper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(url: url))
        player = queuePlayer
        queuePlayer.isMuted = true  // 默认静音，不干扰录制

        let pLayer = AVPlayerLayer(player: queuePlayer)
        pLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(pLayer)
        playerLayer = pLayer
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    /// 跳到开头并从头播放（录制开始时调用，确保跟参考视频同步）
    func restartFromBeginning() {
        player?.pause()
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.player?.play()
        }
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }
}

/// SwiftUI 包装：带拖拽、点击暂停/恢复的 PiP 小窗
struct DraggablePiPView: View {
    let url: URL
    let screenSize: CGSize
    @Binding var isPlaying: Bool
    let restartToken: Int
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var pipWidth: CGFloat { screenSize.width / 3 }
    private var pipHeight: CGFloat { pipWidth * 16 / 9 }

    var body: some View {
        PiPVideoView(url: url, isPlaying: isPlaying, restartToken: restartToken)
            .frame(width: pipWidth, height: pipHeight)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isPlaying.toggle()
                }
            }
            .overlay(
                // 暂停图标
                Group {
                    if !isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            )
    }
}

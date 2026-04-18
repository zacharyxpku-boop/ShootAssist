import SwiftUI
import AVFoundation

/// 画中画参考视频小窗 — 悬浮在相机预览上层，循环播放参考视频
/// 录制时只显示在 UI 上，不录入最终视频
struct PiPVideoView: UIViewRepresentable {
    let url: URL
    let isPlaying: Bool
    /// 每次值变化都会把视频 seek 到 0 + 重新播放（用于录制开始时从头同步）
    let restartToken: Int
    /// 是否解除参考视频自带音轨的静音 — 录制开始时为 true，
    /// 让用户跟着原始音乐节奏跳舞；导入静止预览阶段为 false
    let audioEnabled: Bool

    func makeUIView(context: Context) -> PiPPlayerUIView {
        let view = PiPPlayerUIView(url: url)
        view.setMuted(!audioEnabled)
        context.coordinator.lastToken = restartToken
        context.coordinator.lastURL = url
        return view
    }

    func updateUIView(_ uiView: PiPPlayerUIView, context: Context) {
        if url != context.coordinator.lastURL {
            context.coordinator.lastURL = url
            uiView.replaceSource(url: url)
        }
        // 每次刷新都同步静音状态，audioEnabled 切换瞬间生效
        uiView.setMuted(!audioEnabled)
        if restartToken != context.coordinator.lastToken {
            context.coordinator.lastToken = restartToken
            // isPlaying 决定 restart 后是否继续播放
            // 导入时 token++ 但 isPlaying=false → seek 到 0 静止显示第一帧
            // 开录时 token++ 且 isPlaying=true → seek 到 0 后继续播放
            uiView.seekToZero(thenPlay: isPlaying)
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
        var lastURL: URL?
    }
}

class PiPPlayerUIView: UIView {
    // 不用 AVPlayerLooper（seek/pause 时和内部 queue 有竞态）
    // 改用普通 AVPlayer + 手动监听 didPlayToEnd 重置到 0
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLayer: AVPlayerLayer?
    /// 用户最近一次意图：play() 设 true，pause() 设 false；
    /// loop 重放前要检查这个，避免用户刚暂停就又被 didPlayToEnd 自动续播
    private var shouldLoopPlay: Bool = false

    init(url: URL) {
        super.init(frame: .zero)
        backgroundColor = .black
        layer.cornerRadius = 8
        clipsToBounds = true

        let p = AVPlayer()
        p.actionAtItemEnd = .none
        // 默认静音；调用方通过 setMuted(_:) 控制
        // PiPVideoView.makeUIView 会在创建后立即按 audioEnabled 设置一次
        p.isMuted = true
        player = p

        let pLayer = AVPlayerLayer(player: p)
        // .resizeAspect 保证不裁切参考视频内容（横屏竖屏都完整显示，留黑边）
        pLayer.videoGravity = .resizeAspect
        layer.addSublayer(pLayer)
        playerLayer = pLayer

        replaceSource(url: url)
    }

    /// 替换播放源（用户换参考视频时调用）
    func replaceSource(url: URL) {
        // 先 pause 再换：旧 item 仍在解码的状态下直接 replaceCurrentItem，旧 item
        // 残留的 decode/render 资源释放窗口内若 didReachEnd 通知已在队列中排队，
        // 即使 guard `endedItem === playerItem` 会挡住，也浪费 CPU/带宽
        player?.pause()
        // 先移除旧 item 的 notification observer
        if let oldItem = playerItem {
            NotificationCenter.default.removeObserver(
                self,
                name: .AVPlayerItemDidPlayToEndTime,
                object: oldItem
            )
        }
        let item = AVPlayerItem(url: url)
        playerItem = item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        player?.replaceCurrentItem(with: item)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    @objc private func itemDidReachEnd(_ notification: Notification) {
        // notification object 必须匹配当前 item，防止旧 item 遗留的通知干扰
        guard let endedItem = notification.object as? AVPlayerItem,
              endedItem === playerItem else { return }
        // 尊重 pause 意图：用户主动暂停过就不自动续播
        let shouldResume = shouldLoopPlay
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            if shouldResume { self?.player?.play() }
        }
    }

    func play() {
        shouldLoopPlay = true
        player?.play()
    }

    func pause() {
        shouldLoopPlay = false
        player?.pause()
    }

    /// 跳到开头并从头播放（录制开始时调用，确保跟参考视频同步）
    func restartFromBeginning() {
        seekToZero(thenPlay: true)
    }

    /// 跳到开头，按 thenPlay 决定是否继续播放
    /// thenPlay=false 用于导入后静止在第一帧显示，不自动播
    func seekToZero(thenPlay: Bool) {
        shouldLoopPlay = thenPlay
        player?.pause()
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard finished else { return }
            if thenPlay { self?.player?.play() }
        }
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }
}

/// SwiftUI 包装：带拖拽、捏合缩放、点击暂停/恢复的 PiP 小窗
struct DraggablePiPView: View {
    let url: URL
    let screenSize: CGSize
    @Binding var isPlaying: Bool
    let restartToken: Int
    let audioEnabled: Bool
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    private var pipWidth: CGFloat { screenSize.width / 3 }
    private var pipHeight: CGFloat { pipWidth * 16 / 9 }

    var body: some View {
        PiPVideoView(url: url, isPlaying: isPlaying, restartToken: restartToken, audioEnabled: audioEnabled)
            .frame(width: pipWidth, height: pipHeight)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                SimultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in lastOffset = offset },
                    MagnificationGesture()
                        .onChanged { value in
                            // 限制 0.5x ~ 2.5x，避免缩到看不见或撑满屏幕
                            scale = min(max(lastScale * value, 0.5), 2.5)
                        }
                        .onEnded { _ in lastScale = scale }
                )
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

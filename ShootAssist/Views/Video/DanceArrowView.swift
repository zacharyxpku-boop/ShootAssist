import SwiftUI

// MARK: - 手势舞动作引导（具体动作描述 + 匹配状态）
struct DanceGuideView: View {
    let currentMove: DanceMove?
    let nextMove: DanceMove?

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 10) {
            if let move = currentMove {
                VStack(spacing: 4) {
                    Text(move.icon)
                        .font(.system(size: 36))
                        .scaleEffect(pulseScale)
                    Text(move.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .rosePink.opacity(0.6), radius: 4)
                }
                .transition(.scale.combined(with: .opacity))
                .id("move_\(move.id)")
            }

            if let next = nextMove {
                HStack(spacing: 6) {
                    Text("下一个").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                    Text(next.icon).font(.system(size: 16))
                    Text(next.description).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.35)))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulseScale = 1.15 }
        }
    }
}

// MARK: - 节拍进度条（基于动作间隔）
struct BeatProgressBar: View {
    /// 当前动作在舞蹈中的进度比例（0-1）
    var moveProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 2.5)
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * moveProgress, 4), height: 2.5)
                    .animation(.easeInOut(duration: 0.3), value: moveProgress)
            }
        }
        .frame(height: 2.5)
    }
}

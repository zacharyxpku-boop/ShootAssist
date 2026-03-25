import SwiftUI

// MARK: - 对口型歌词显示（时间轴驱动）
struct LyricsView: View {
    let lines: [LyricLine]
    let currentIndex: Int
    let playbackTime: TimeInterval

    private var safeIndex: Int {
        guard !lines.isEmpty else { return 0 }
        return min(currentIndex, lines.count - 1)
    }

    var body: some View {
        VStack(spacing: 6) {
            if !lines.isEmpty {
                // 当前行 + 进度指示
                VStack(spacing: 4) {
                    Text(lines[safeIndex].text)
                        .font(.system(size: 14, weight: .semibold))
                        .tracking(2)
                        .foregroundColor(.white)
                        .shadow(color: .rosePink.opacity(0.6), radius: 4)
                        .id("lyric_\(safeIndex)")
                        .transition(.opacity)

                    // 当前句进度条
                    GeometryReader { geo in
                        let line = lines[safeIndex]
                        let duration = line.endTime - line.startTime
                        let elapsed = playbackTime - line.startTime
                        let progress = duration > 0 ? min(1, max(0, elapsed / duration)) : 0

                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.rosePink.opacity(0.6))
                            .frame(width: geo.size.width * CGFloat(progress))
                            .animation(.linear(duration: 0.1), value: progress)
                    }
                    .frame(height: 2)
                    .padding(.horizontal, 10)
                }

                // 下一行预览
                let nextIndex = safeIndex + 1
                if nextIndex < lines.count {
                    Text(lines[nextIndex].text)
                        .font(.system(size: 12))
                        .tracking(2)
                        .foregroundColor(.white.opacity(0.45))
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.35))
        )
        .animation(.easeInOut(duration: 0.3), value: safeIndex)
    }
}

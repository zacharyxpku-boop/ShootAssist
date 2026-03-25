import SwiftUI

struct AnimatedCard<Content: View>: View {
    let content: () -> Content
    let onTap: () -> Void

    @State private var isPressed = false
    @State private var shimmerOffset: CGFloat = -200

    init(onTap: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        content()
            .background(
                ZStack {
                    // 磨砂玻璃 + 白色叠加
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.white.opacity(0.65))

                    // 顶部高光线
                    VStack {
                        LinearGradient(
                            colors: [.clear, .rosePink.opacity(0.3), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(height: 1.5)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        Spacer()
                    }

                    // 高光扫过效果
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.4), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .offset(x: shimmerOffset)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .opacity(isPressed ? 1 : 0)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.sakuraPink, lineWidth: 1.5)
            )
            .shadow(color: .rosePink.opacity(isPressed ? 0.06 : 0.12), radius: 16, y: 4)
            .scaleEffect(isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            shimmerOffset = -200
                            withAnimation(.easeInOut(duration: 0.5)) {
                                shimmerOffset = 400
                            }
                        }
                    }
                    .onEnded { value in
                        isPressed = false
                        // 判断手指是否在卡片范围内松开（简单判断位移小于 20pt 视为点击）
                        let dx = abs(value.translation.width)
                        let dy = abs(value.translation.height)
                        if dx < 20 && dy < 20 {
                            // 延迟一小段让弹回动画播放
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onTap()
                            }
                        }
                    }
            )
    }
}

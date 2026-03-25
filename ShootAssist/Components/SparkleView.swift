import SwiftUI

// MARK: - 单个闪烁星星
struct SparkleSymbol: View {
    let size: CGFloat
    let x: CGFloat
    let y: CGFloat
    let delay: Double

    @State private var opacity: Double = 0.3

    var body: some View {
        Text("✦")
            .font(.system(size: size))
            .foregroundStyle(
                LinearGradient(
                    colors: [.rosePink, .peachPink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .opacity(opacity)
            .position(x: x, y: y)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 2.5)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    opacity = 0.8
                }
            }
    }
}

// MARK: - 星星装饰背景层
struct SparkleField: View {
    struct StarConfig: Identifiable {
        let id = UUID()
        let size: CGFloat
        let xRatio: CGFloat
        let yRatio: CGFloat
        let delay: Double
    }

    let stars: [StarConfig] = [
        StarConfig(size: 10, xRatio: 0.15, yRatio: 0.12, delay: 0),
        StarConfig(size: 7, xRatio: 0.82, yRatio: 0.08, delay: 0.5),
        StarConfig(size: 13, xRatio: 0.68, yRatio: 0.35, delay: 1.0),
        StarConfig(size: 8, xRatio: 0.25, yRatio: 0.55, delay: 1.5),
        StarConfig(size: 11, xRatio: 0.9, yRatio: 0.65, delay: 0.8),
    ]

    var body: some View {
        GeometryReader { geo in
            ForEach(stars) { star in
                SparkleSymbol(
                    size: star.size,
                    x: geo.size.width * star.xRatio,
                    y: geo.size.height * star.yRatio,
                    delay: star.delay
                )
            }
        }
    }
}

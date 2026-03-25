import SwiftUI

// MARK: - 首次启动引导（3 页）
// 通过 @AppStorage("hasSeenOnboarding") 控制只展示一次

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "📷",
            title: "不修图，拍就好看",
            subtitle: "AI 实时告诉你怎么站、怎么构图\n闭眼预警 · 黄金分割线 · 瞬间抓准",
            gradient: [Color(hex: "FF85A1"), Color(hex: "FFB3CC")]
        ),
        OnboardingPage(
            icon: "🎬",
            title: "把任意舞蹈变成引导",
            subtitle: "导入一段跳舞视频，AI 自动提取手势\n跟着 emoji 节拍录制，简单上手",
            gradient: [Color(hex: "FFCBA4"), Color(hex: "FF85A1")]
        ),
        OnboardingPage(
            icon: "💡",
            title: "拍之前先找好 Pose",
            subtitle: "40+ 网红 Pose 图解 · 附带机位建议\n照着做，拍就好看",
            gradient: [Color(hex: "E8C4FF"), Color(hex: "FFCBA4")]
        ),
    ]

    var body: some View {
        ZStack {
            // 背景渐变随页面变色
            LinearGradient(
                colors: pages[currentPage].gradient.map { $0.opacity(0.15) } + [Color.white],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: currentPage)

            VStack(spacing: 0) {
                Spacer()

                // 页面内容
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        PageContent(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 380)

                // 分页指示器
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        if i == currentPage {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: pages[currentPage].gradient,
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: 24, height: 7)
                        } else {
                            Circle()
                                .fill(Color.gray.opacity(0.25))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .animation(.spring(response: 0.3), value: currentPage)
                .padding(.top, 20)

                Spacer()

                // 按钮
                VStack(spacing: 12) {
                    if currentPage < pages.count - 1 {
                        Button(action: {
                            withAnimation { currentPage += 1 }
                        }) {
                            Text("下一步")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(
                                    Capsule().fill(LinearGradient(
                                        colors: pages[currentPage].gradient,
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                )
                        }
                        .accessibilityLabel("下一步")
                    } else {
                        Button(action: { isPresented = false }) {
                            Text("开始使用 ✦")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(
                                    Capsule().fill(LinearGradient(
                                        colors: [Color(hex: "FF85A1"), Color(hex: "FFCBA4")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                )
                        }
                        .accessibilityLabel("开始使用小白快门")
                    }

                    Button(action: { isPresented = false }) {
                        Text("跳过")
                            .font(.system(size: 13))
                            .foregroundColor(.gray.opacity(0.6))
                    }
                    .accessibilityLabel("跳过引导")
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - 单页内容

private struct PageContent: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            // 大图标
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: page.gradient.map { $0.opacity(0.2) },
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 120, height: 120)
                Text(page.icon)
                    .font(.system(size: 56))
            }

            VStack(spacing: 10) {
                Text(page.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "3D2A2F"))

                Text(page.subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: "8B6E75"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - 数据模型

private struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
}

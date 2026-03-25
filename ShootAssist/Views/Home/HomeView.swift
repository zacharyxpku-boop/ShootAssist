import SwiftUI

struct HomeView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @State private var navigateToPhoto = false
    @State private var navigateToVideo = false
    @State private var navigateToPoseLibrary = false
    @State private var showPaywall = false
    @State private var logoOffset: CGFloat = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [.warmCream, .lightPink, .lavenderPink],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()

                GlowOrbs()
                SparkleField()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer().frame(height: 50)

                        // Logo + Pro 状态
                        ZStack(alignment: .topTrailing) {
                            LogoSection(logoOffset: logoOffset)
                            if subManager.isPro {
                                ProBadgePill(label: "Pro ✓", isPro: true)
                                    .offset(x: 8, y: 0)
                            } else {
                                Button(action: { showPaywall = true }) {
                                    ProBadgePill(label: "升级 Pro", isPro: false)
                                }
                                .accessibilityLabel("升级到 Pro 版")
                                .offset(x: 8, y: 0)
                            }
                        }

                        Spacer().frame(height: 10)

                        // 差异化 slogan
                        TaglineCapsule()

                        Spacer().frame(height: 28)

                        // 三张功能卡片
                        VStack(spacing: 14) {
                            AnimatedCard(onTap: { navigateToPhoto = true }) {
                                PhotoCardContent()
                            }

                            AnimatedCard(onTap: { navigateToVideo = true }) {
                                VideoCardContent(isPro: subManager.isPro)
                            }

                            AnimatedCard(onTap: { navigateToPoseLibrary = true }) {
                                PoseCardContent()
                            }
                        }
                        .padding(.horizontal, 24)

                        Spacer().frame(height: 24)

                        // 底部指示器
                        PageIndicator(currentPage: 0)
                            .padding(.bottom, 30)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToPhoto) {
                PhotoModeView()
            }
            .navigationDestination(isPresented: $navigateToVideo) {
                VideoModeView()
                    .environmentObject(subManager)
            }
            .navigationDestination(isPresented: $navigateToPoseLibrary) {
                PoseLibraryView()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                logoOffset = 4
            }
        }
    }
}

// MARK: - 光晕
private struct GlowOrbs: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.rosePink.opacity(0.25))
                .frame(width: 200, height: 200).blur(radius: 80)
                .offset(x: 120, y: -280)
            Circle().fill(Color.honeyOrange.opacity(0.2))
                .frame(width: 180, height: 180).blur(radius: 70)
                .offset(x: -130, y: 200)
            Circle().fill(Color.peachPink.opacity(0.18))
                .frame(width: 160, height: 160).blur(radius: 60)
                .offset(x: -100, y: -50)
        }
    }
}

// MARK: - Logo
private struct LogoSection: View {
    let logoOffset: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [.rosePink, .peachPink, .honeyOrange],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 60, height: 60)
                    .overlay(Text("📸").font(.system(size: 28)))
                    .shadow(color: .rosePink.opacity(0.3), radius: 12, y: 4)

                SparkleSymbol(size: 12, x: 8, y: 8, delay: 0)
                    .frame(width: 16, height: 16)
                    .offset(x: 8, y: -8)
            }
            .offset(y: logoOffset)

            Text("小白快门")
                .font(.system(size: 22, weight: .bold))
                .tracking(3)
                .foregroundStyle(LinearGradient(
                    colors: [.deepRose, .rosePink, .honeyOrange],
                    startPoint: .leading, endPoint: .trailing
                ))

            Text("不修图，拍就好看")
                .font(.system(size: 11, weight: .medium))
                .tracking(1)
                .foregroundColor(.midBerryBrown)
        }
    }
}

// MARK: - 标语胶囊
private struct TaglineCapsule: View {
    var body: some View {
        Text("✨ AI教你构图 · 帮你摆pose · 一拍就对")
            .font(.system(size: 10))
            .foregroundColor(.midBerryBrown)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.white.opacity(0.6))
                    .overlay(Capsule().stroke(Color.sakuraPink, lineWidth: 1))
            )
    }
}

// MARK: - 照片卡片
private struct PhotoCardContent: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.sakuraPink, .peachPink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 46)
                .overlay(Text("📷").font(.system(size: 22)))

            VStack(alignment: .leading, spacing: 3) {
                Text("拍照")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.berryBrown)
                Text("AI实时构图 · 网红Pose复刻 · 闭眼提醒")
                    .font(.system(size: 10))
                    .foregroundColor(.paleRose)
            }
            Spacer()
            Text("›").font(.system(size: 18, weight: .medium)).foregroundColor(.peachPink)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .topTrailing) {
            Text("热门")
                .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient(
                    colors: [.rosePink, .deepRose], startPoint: .leading, endPoint: .trailing)))
                .offset(x: -10, y: -6)
        }
    }
}

// MARK: - Pro 状态胶囊
private struct ProBadgePill: View {
    let label: String
    let isPro: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(isPro ? Color(hex: "FF5A7E") : .white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isPro
                    ? Color(hex: "FF85A1").opacity(0.15)
                    : LinearGradient(colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                     startPoint: .leading, endPoint: .trailing)
                )
            )
            .overlay(
                Capsule()
                    .stroke(isPro ? Color(hex: "FF85A1").opacity(0.3) : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - 视频卡片
private struct VideoCardContent: View {
    let isPro: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(hex: "FFE0CC"), .honeyOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 46)
                .overlay(Text("🎬").font(.system(size: 22)))

            VStack(alignment: .leading, spacing: 3) {
                Text("录像")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.berryBrown)
                Text(isPro ? "手势舞 · 歌词对口型 · 跟视频跳" : "手势舞 · 歌词对口型 · 跟视频跳 🔒")
                    .font(.system(size: 10))
                    .foregroundColor(.paleRose)
            }
            Spacer()
            Text("›").font(.system(size: 18, weight: .medium)).foregroundColor(.honeyOrange)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }
}

// MARK: - Pose 灵感卡片（新增）
private struct PoseCardContent: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.lavenderPink, .rosePink.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 46)
                .overlay(Text("💡").font(.system(size: 22)))

            VStack(alignment: .leading, spacing: 3) {
                Text("灵感")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.berryBrown)
                Text("40+ 热门Pose · 拍照技巧速学")
                    .font(.system(size: 10))
                    .foregroundColor(.paleRose)
            }
            Spacer()
            Text("›").font(.system(size: 18, weight: .medium)).foregroundColor(.rosePink)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .overlay(alignment: .topTrailing) {
            Text("新")
                .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient(
                    colors: [.honeyOrange, .deepRose], startPoint: .leading, endPoint: .trailing)))
                .offset(x: -10, y: -6)
        }
    }
}

// MARK: - 页面指示器
private struct PageIndicator: View {
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                if index == currentPage {
                    Capsule()
                        .fill(LinearGradient(colors: [.rosePink, .peachPink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 20, height: 6)
                } else {
                    Circle().fill(Color.sakuraPink).frame(width: 6, height: 6)
                }
            }
        }
    }
}

#Preview { HomeView() }

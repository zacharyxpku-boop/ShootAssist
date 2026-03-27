import SwiftUI

struct HomeView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @State private var navigateToClone = false      // 拍同款直通
    @State private var navigateToPhoto = false      // 普通拍照
    @State private var navigateToVideo = false
    @State private var navigateToPoseLibrary = false
    @State private var showPaywall = false
    @State private var logoOffset: CGFloat = 0
    @State private var heroPulse = false

    var body: some View {
        NavigationStack {
            ZStack {
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
                                ProBadgePill(label: "Pro ✓", isPro: true).offset(x: 8, y: 0)
                            } else {
                                Button(action: { showPaywall = true }) {
                                    ProBadgePill(label: "升级 Pro", isPro: false)
                                }
                                .accessibilityLabel("升级到 Pro 版")
                                .offset(x: 8, y: 0)
                            }
                        }

                        Spacer().frame(height: 20)

                        // ── HERO：拍同款 ──────────────────────────────
                        HeroCloneCard(pulse: heroPulse) {
                            navigateToClone = true
                        }
                        .padding(.horizontal, 20)

                        Spacer().frame(height: 14)

                        // ── 次要功能行：录像 + Pose 灵感 ───────────────
                        HStack(spacing: 12) {
                            AnimatedCard(onTap: { navigateToVideo = true }) {
                                SmallVideoCard(isPro: subManager.isPro)
                            }
                            AnimatedCard(onTap: { navigateToPoseLibrary = true }) {
                                SmallPoseCard()
                            }
                        }
                        .padding(.horizontal, 20)

                        // ── 拍照入口（弱化，藏在下面）──────────────────
                        Button(action: { navigateToPhoto = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "camera").font(.system(size: 12))
                                Text("更多拍照功能")
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.right").font(.system(size: 10))
                            }
                            .foregroundColor(.midBerryBrown.opacity(0.7))
                            .padding(.top, 18)
                        }

                        Spacer().frame(height: 40)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // 拍同款直通：进入 PhotoModeView 并自动选图
            .navigationDestination(isPresented: $navigateToClone) {
                PhotoModeView(launchCloneDirectly: true)
            }
            .navigationDestination(isPresented: $navigateToPhoto) {
                PhotoModeView()
            }
            .navigationDestination(isPresented: $navigateToVideo) {
                VideoModeView().environmentObject(subManager)
            }
            .navigationDestination(isPresented: $navigateToPoseLibrary) {
                PoseLibraryView()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subManager)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { logoOffset = 4 }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { heroPulse = true }
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

// MARK: - Hero 拍同款卡（首页唯一焦点）

private struct HeroCloneCard: View {
    let pulse: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // 背景渐变
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .shadow(color: Color(hex: "FF5A7E").opacity(0.35), radius: 18, y: 8)

                // 内容
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        // 标题
                        VStack(alignment: .leading, spacing: 4) {
                            Text("看到好看的照片？")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            Text("教你拍同款")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white.opacity(0.92))
                        }

                        // 说明
                        Text("上传参考图 · AI 识别姿势\n实时对齐，闭眼就能拍出来")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.8))
                            .lineSpacing(3)

                        // 按钮
                        HStack(spacing: 6) {
                            Text("立刻试试")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(hex: "FF5A7E"))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "FF5A7E"))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(.white))
                        .scaleEffect(pulse ? 1.03 : 1.0)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulse)
                    }
                    .padding(24)

                    Spacer()

                    // 右侧大 emoji
                    Text("🪞")
                        .font(.system(size: 64))
                        .padding(.trailing, 20)
                        .offset(y: -4)
                }
            }
            .frame(height: 170)
        }
        .accessibilityLabel("拍同款，上传参考图 AI 帮你实时对齐")
    }
}

// MARK: - 次要功能小卡（录像）

private struct SmallVideoCard: View {
    let isPro: Bool
    var body: some View {
        HStack(spacing: 10) {
            Text("🎬").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("录像").font(.system(size: 14, weight: .bold)).foregroundColor(.berryBrown)
                Text("手势舞 · 对口型").font(.system(size: 10)).foregroundColor(.paleRose)
            }
            Spacer()
            if !isPro {
                Image(systemName: "lock.fill").font(.system(size: 10)).foregroundColor(.honeyOrange)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }
}

// MARK: - 次要功能小卡（Pose 灵感）

private struct SmallPoseCard: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("💡").font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text("Pose 灵感").font(.system(size: 14, weight: .bold)).foregroundColor(.berryBrown)
                Text("40+ 热门 Pose").font(.system(size: 10)).foregroundColor(.paleRose)
            }
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
    }
}

// MARK: - 照片卡片（保留，供"更多拍照功能"入口使用）
private struct PhotoCardContent: View {
    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [.sakuraPink, .peachPink], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 46, height: 46)
                .overlay(Text("📷").font(.system(size: 22)))
            VStack(alignment: .leading, spacing: 3) {
                Text("拍照").font(.system(size: 15, weight: .bold)).foregroundColor(.berryBrown)
                Text("AI构图 · 机位提示").font(.system(size: 10)).foregroundColor(.paleRose)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
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

import SwiftUI

// MARK: - Paywall（v1.0 改成「免费版感谢页」）
//
// v1.0 全员免费、不接 StoreKit。这个 View 名字和入口都保留，
// 但 body 已不再展示价格/购买按钮，避免 Apple 审核员看到 IAP UI 但
// Product.products(for:) 又返回空，触发「infinite loading」拒审。
//
// 任何残留的 showPaywall = true 触发都会落到这个友好提示页，
// 用户点「好的」直接关闭。后续 v1.0.1 接回订阅时 git revert 即可。

struct PaywallView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 背景渐变与原 Paywall 一致，保持视觉延续
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color(hex: "FFFAF5"), Color.white],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // 关闭按钮（右上角 44x44 触控区 — 满足无障碍）
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.gray.opacity(0.65))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.gray.opacity(0.1)))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("关闭")
            .padding(.top, 8)
            .padding(.trailing, 12)

            VStack(spacing: 22) {
                Spacer()

                // 心心图标
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "FF85A1").opacity(0.18),
                                     Color(hex: "FFCBA4").opacity(0.18)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 110, height: 110)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(hex: "FF6B8A"), Color(hex: "FFB088")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                }

                Text("全部功能 已经免费啦")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: "5A2A3A"))

                VStack(spacing: 6) {
                    Text("v1.0 阶段不收订阅费")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(hex: "8B5C70"))
                    Text("拍同款 / 爆款姿势 / 视频画中画\n通通无限使用，谢谢一路陪我走到这里 ✨")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "8B5C70"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
                .padding(.horizontal, 32)

                Spacer()

                // 主按钮：关闭
                Button(action: { dismiss() }) {
                    Text("继续拍照")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            Capsule().fill(LinearGradient(
                                colors: [Color(hex: "FF85A1"), Color(hex: "FFCBA4")],
                                startPoint: .leading, endPoint: .trailing
                            ))
                        )
                }
                .accessibilityLabel("继续拍照")
                .padding(.horizontal, 30)

                // 次按钮：把 App 推荐给朋友（轻量裂变钩子）
                Button(action: {
                    UIPasteboard.general.string = ReferralManager.shareAppendText()
                    dismiss()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text("复制邀请文案")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Color(hex: "8B5C70"))
                }
                .accessibilityLabel("复制邀请文案分享给朋友")
                .padding(.bottom, 36)
            }
            .padding(.top, 40)
        }
    }
}

#Preview {
    PaywallView().environmentObject(SubscriptionManager())
}

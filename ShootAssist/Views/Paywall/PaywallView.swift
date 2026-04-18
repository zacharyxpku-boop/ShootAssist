import SwiftUI
import StoreKit
import UIKit

// MARK: - 付费墙（Paywall）

struct PaywallView: View {
    @EnvironmentObject var subManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String = SubscriptionManager.annualID
    @State private var showErrorAlert = false

    var body: some View {
        ZStack(alignment: .top) {
            // 背景渐变
            LinearGradient(
                colors: [Color(hex: "FFF0F5"), Color(hex: "FFFAF5"), Color.white],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 关闭按钮
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray.opacity(0.55))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.gray.opacity(0.1)))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("关闭")
                    .padding(.trailing, 12)
                    .padding(.top, 8)
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {

                        // MARK: Hero
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "FF85A1").opacity(0.18),
                                                 Color(hex: "FFCBA4").opacity(0.18)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 96, height: 96)
                                Text("👑")
                                    .font(.system(size: 46))
                            }

                            Text("小白快门 Pro")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(LinearGradient(
                                    colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))

                            Text("你拍的视频，值得被更多人看到")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "8B6E75"))
                        }
                        .padding(.top, 4)

                        // MARK: 功能列表
                        VStack(spacing: 0) {
                            ProFeatureRow(emoji: "🪞",
                                          title: "无限次拍同款",
                                          subtitle: "免费版每天 3 次，Pro 无限拍\n上传任意参考图，AI 实时骨骼对齐")
                            Divider().padding(.horizontal, 16).opacity(0.4)

                            ProFeatureRow(emoji: "📸",
                                          title: "拍完自动生成对比拼图",
                                          subtitle: "参考图 vs 你拍的，左右对比\n带匹配度「87%」直接发小红书")
                            Divider().padding(.horizontal, 16).opacity(0.4)

                            ProFeatureRow(emoji: "🎬",
                                          title: "导入任意舞蹈视频跟拍",
                                          subtitle: "不只是 Demo，想跟哪首跟哪首\nAI 30 秒提取动作引导，emoji 提示跟着跳")
                            Divider().padding(.horizontal, 16).opacity(0.4)

                            ProFeatureRow(emoji: "🚀",
                                          title: "新功能第一个用",
                                          subtitle: "AR Pose 叠加等上线 Pro 先解锁\n视频录制完自动加「小白快门」水印")
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white)
                                .shadow(color: Color(hex: "FF85A1").opacity(0.08),
                                        radius: 12, y: 4)
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        // MARK: 产品卡片
                        VStack(spacing: 10) {
                            if subManager.products.isEmpty {
                                ProgressView()
                                    .tint(Color(hex: "FF85A1"))
                                    .frame(height: 60)
                            } else {
                                ForEach(subManager.products, id: \.id) { product in
                                    ProProductCard(
                                        product: product,
                                        isSelected: selectedProductID == product.id,
                                        onTap: { selectedProductID = product.id }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // MARK: 免费试用提示
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text("✨")
                                    .font(.system(size: 13))
                                Text("解锁全部姿势库 + 无限拍同款")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color(hex: "8B6E75"))
                            }
                        }
                        .padding(.top, 14)

                        // MARK: 购买按钮
                        Button(action: handlePurchase) {
                            ZStack {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .shadow(color: Color(hex: "FF5A7E").opacity(0.3),
                                            radius: 10, y: 4)
                                if subManager.isPurchasing {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("立即解锁 Pro ✦")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white)
                                }
                            }
                            .frame(height: 52)
                        }
                        .disabled(subManager.isPurchasing || subManager.products.isEmpty)
                        .accessibilityLabel("立即解锁 Pro")
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                        // 免费试用提示 — 只在选中的产品确实带 introductoryOffer 时才显示
                        // App Review 会对"3 天免费"类文案做 StoreKit 真实性核查，静态文案容易被打回
                        if let offerText = introductoryOfferText(for: selectedProductID) {
                            Text(offerText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(hex: "FF8C42"))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 30)
                                .padding(.top, 8)
                        }

                        // 自动续费说明
                        Text("订阅到期自动续费，可随时在「设置 › Apple ID › 订阅」中取消")
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.45))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                            .padding(.top, 10)

                        // 恢复 & 链接
                        HStack(spacing: 0) {
                            Button("恢复购买") {
                                Task { await subManager.restorePurchases() }
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.gray.opacity(0.55))

                            Text("  ·  ")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.3))

                            Button("隐私政策") { openURL("https://shootassist.app/privacy") }
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.55))

                            Text("  ·  ")
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.3))

                            Button("服务条款") { openURL("https://shootassist.app/terms") }
                                .font(.system(size: 12))
                                .foregroundColor(.gray.opacity(0.55))
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .onAppear {
            preselectAnnual()
            Analytics.track(Analytics.Event.paywallViewed)
        }
        .onChange(of: subManager.products) { _ in preselectAnnual() }
        .onChange(of: subManager.isPro) { isPro in
            if isPro { dismiss() }
        }
        .onChange(of: subManager.purchaseError) { err in
            if err != nil { showErrorAlert = true }
        }
        .alert("提示", isPresented: $showErrorAlert) {
            Button("好的") { subManager.purchaseError = nil }
        } message: {
            Text(subManager.purchaseError ?? "")
        }
        // 整页基于亮色渐变+深色文字，强制 light 避免暗色模式下文字/卡片对比度崩盘
        .preferredColorScheme(.light)
    }

    // MARK: - 辅助

    private func preselectAnnual() {
        if subManager.products.contains(where: { $0.id == SubscriptionManager.annualID }) {
            selectedProductID = SubscriptionManager.annualID
        } else if let first = subManager.products.first {
            selectedProductID = first.id
        }
    }

    private func handlePurchase() {
        let product = subManager.products.first(where: { $0.id == selectedProductID })
                   ?? subManager.products.first
        guard let product else { return }
        Task { await subManager.purchase(product) }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        UIApplication.shared.open(url)
    }

    /// 动态判定选中产品是否带介绍性优惠（免费试用 / 折扣首期）
    /// App Review 会核查文案和 StoreKit 实际配置的一致性，静态写死容易被打回
    private func introductoryOfferText(for productID: String) -> String? {
        guard let product = subManager.products.first(where: { $0.id == productID }),
              let offer = product.subscription?.introductoryOffer else {
            return nil
        }
        let periodText: String = {
            let count = offer.period.value
            switch offer.period.unit {
            case .day:   return "\(count) 天"
            case .week:  return "\(count) 周"
            case .month: return "\(count) 个月"
            case .year:  return "\(count) 年"
            @unknown default: return ""
            }
        }()
        switch offer.paymentMode {
        case .freeTrial:
            return "首次订阅享 \(periodText)免费体验，到期前取消不扣费"
        case .payAsYouGo, .payUpFront:
            return "首次订阅 \(periodText)享特惠价 \(offer.displayPrice)"
        default:
            return nil
        }
    }
}

// MARK: - 功能特性行

private struct ProFeatureRow: View {
    let emoji: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color(hex: "FFF0F5")))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "3D2A2F"))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "8B6E75"))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "FF85A1"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - 产品卡片

private struct ProProductCard: View {
    let product: Product
    let isSelected: Bool
    let onTap: () -> Void

    private var isAnnual: Bool { product.id.contains("annual") }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 选择指示器
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color(hex: "FF5A7E") : Color.gray.opacity(0.3),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color(hex: "FF5A7E"))
                            .frame(width: 13, height: 13)
                    }
                }

                // 方案名称
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isAnnual ? "年度订阅" : "月度订阅")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "3D2A2F"))

                        if isAnnual {
                            Text("最受欢迎")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(LinearGradient(
                                            colors: [Color(hex: "FF5A7E"), Color(hex: "FF8C42")],
                                            startPoint: .leading, endPoint: .trailing
                                        ))
                                )
                        }
                    }
                    HStack(spacing: 6) {
                        Text(isAnnual ? "折合每月 \(monthlyEquivalent)" : "随时取消")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "8B6E75"))
                        if isAnnual {
                            Text("省约 50%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "FF5A7E"))
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    Capsule().fill(Color(hex: "FF5A7E").opacity(0.1))
                                )
                        }
                    }
                }

                Spacer()

                // 价格
                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "3D2A2F"))
                    Text(isAnnual ? "/年" : "/月")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "8B6E75"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color(hex: "FFF0F5") : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                isSelected ? Color(hex: "FF85A1") : Color.gray.opacity(0.15),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: isSelected ? Color(hex: "FF85A1").opacity(0.1) : .clear,
                        radius: 8, y: 2
                    )
            )
        }
        .accessibilityLabel(isAnnual ? "年度订阅，\(product.displayPrice)" : "月度订阅，\(product.displayPrice)")
    }

    /// 年订阅折合月价（用于显示）
    private var monthlyEquivalent: String {
        let monthly = product.price / 12
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = 1
        return formatter.string(from: monthly as NSDecimalNumber) ?? ""
    }
}

import StoreKit

// MARK: - 订阅管理（StoreKit 2）
// 产品 ID 需在 App Store Connect 创建后与此处保持一致

@MainActor
final class SubscriptionManager: ObservableObject {

    // 产品标识符（需在 App Store Connect 中创建对应的自动续期订阅）
    static let annualID  = "com.shootassist.pro.annual"
    static let monthlyID = "com.shootassist.pro.monthly"

    private let productIDs: Set<String> = [annualID, monthlyID]

    @Published var isPro = false
    @Published var products: [Product] = []    // 按月价升序：monthly → annual
    @Published var isPurchasing = false
    @Published var purchaseError: String? = nil

    private var transactionListener: Task<Void, Error>?

    init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshStatus()
        }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - 加载产品列表

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: productIDs)
            // 月价从低到高排序，使月订阅在前、年订阅在后
            products = fetched.sorted { $0.price < $1.price }
            // 若未找到产品（沙盒无 StoreKit 配置），products 保持空，UI 显示 loading
        } catch {
            saLog("[StoreKit] loadProducts failed: \(error.localizedDescription)")
            // 3 秒后自动重试一次
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            do {
                let fetched = try await Product.products(for: productIDs)
                products = fetched.sorted { $0.price < $1.price }
            } catch {
                saLog("[StoreKit] retry also failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 购买

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshStatus()
                let plan = product.id.contains("annual") ? "annual" : "monthly"
                Analytics.track(Analytics.Event.subscriptionPurchased, properties: ["plan": plan])
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "支付未完成，请稍后再试一次"
        }
    }

    // MARK: - 恢复购买

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }

        do {
            try await AppStore.sync()
            await refreshStatus()
            if isPro { Analytics.track(Analytics.Event.subscriptionRestored) }
        } catch {
            purchaseError = "恢复失败，确认网络连接后再试一次"
        }
    }

    // MARK: - 刷新订阅状态

    func refreshStatus() async {
        var hasPro = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  productIDs.contains(tx.productID),
                  tx.revocationDate == nil else { continue }
            hasPro = true
            break
        }
        isPro = hasPro
    }

    // MARK: - 内部工具

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached(priority: .background) { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let tx) = result { await tx.finish() }
                await self.refreshStatus()
            }
        }
    }
}

import StoreKit

// MARK: - 订阅管理（StoreKit 2）
// 产品 ID 需在 App Store Connect 创建后与此处保持一致

@MainActor
final class SubscriptionManager: ObservableObject {

    // 产品标识符（需在 App Store Connect 中创建对应的自动续期订阅）
    static let annualID  = "com.shootassist.pro.annual"
    static let monthlyID = "com.shootassist.pro.monthly"

    private let productIDs: Set<String> = [annualID, monthlyID]

    /// UserDefaults key：试用期结束时间戳（Double，timeIntervalSince1970）
    private static let trialEndDateKey = "pro_trial_end_date"

    @Published var isPro = false
    @Published var products: [Product] = []    // 按月价升序：monthly → annual
    @Published var isPurchasing = false
    @Published var purchaseError: String? = nil
    /// 两轮 loadProducts 都失败后的用户可见错误；Paywall 需要读这个给「重试」按钮
    @Published var loadError: String? = nil

    /// 邀请奖励试用期结束时间；nil = 无试用。试用期内 isPro 同样为 true，但不是真订阅。
    @Published var trialEndDate: Date? = nil

    private var transactionListener: Task<Void, Error>?

    init() {
        // 先从本地恢复试用期，避免冷启动瞬间 isPro 闪烁
        if let ts = UserDefaults.standard.object(forKey: Self.trialEndDateKey) as? Double {
            let date = Date(timeIntervalSince1970: ts)
            if date > Date() {
                trialEndDate = date
                isPro = true
            } else {
                // 已过期的残留 key 顺手清掉
                UserDefaults.standard.removeObject(forKey: Self.trialEndDateKey)
            }
        }
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshStatus()
        }
    }

    // MARK: - 试用期（邀请奖励）

    /// 发放 / 延长 Pro 试用期。
    /// - 无试用或已过期 → 从现在起 days 天
    /// - 试用期内 → 在现有 trialEndDate 基础上延长 days 天（叠加而非重置）
    func grantTrial(days: Int) {
        let now = Date()
        let base: Date
        if let end = trialEndDate, end > now {
            base = end            // 续期：接在现有到期日之后
        } else {
            base = now            // 新开：从当下起算
        }
        let newEnd = base.addingTimeInterval(TimeInterval(days) * 86_400)
        trialEndDate = newEnd
        UserDefaults.standard.set(newEnd.timeIntervalSince1970, forKey: Self.trialEndDateKey)
        isPro = true
        Analytics.track("trial_granted", properties: ["days": days])
    }

    /// 试用剩余天数（向上取整，≤0 返回 0）。UI 展示用。
    var trialDaysRemaining: Int {
        guard let end = trialEndDate else { return 0 }
        let secs = end.timeIntervalSinceNow
        guard secs > 0 else { return 0 }
        return Int(ceil(secs / 86_400))
    }

    deinit { transactionListener?.cancel() }

    // MARK: - 加载产品列表

    func loadProducts() async {
        loadError = nil
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
                // 两次都失败：给 UI 一个可见错误信号，避免 Paywall 永远 spinner
                loadError = "订阅信息加载失败，请检查网络后点击重试"
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
                // 已经 verified 的 tx 就是 Pro；先乐观置位，再让 refreshStatus 作为补偿校验。
                // 避免 refreshStatus 读 entitlements 时若网络抖动返回空，用户钱扣了但 Pro 未解锁。
                isPro = true
                await refreshStatus()
                // 付费用户不需要「试用到期前 24h」的提醒骚扰
                TrialNotificationScheduler.shared.cancelTrialExpiryReminder()
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
        var hasRealSub = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result,
                  productIDs.contains(tx.productID),
                  tx.revocationDate == nil else { continue }
            hasRealSub = true
            break
        }

        // 试用期过期则清空，避免老数据让 isPro 一直 true
        var trialActive = false
        if let end = trialEndDate {
            if end > Date() {
                trialActive = true
            } else {
                trialEndDate = nil
                UserDefaults.standard.removeObject(forKey: Self.trialEndDateKey)
                // 试用已过期，pending 的 24h 提醒若还在也没意义了
                TrialNotificationScheduler.shared.cancelTrialExpiryReminder()
            }
        }

        // 真订阅 OR 有效试用，任一即 Pro
        isPro = hasRealSub || trialActive
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
                // self 临时为 nil 不代表 manager 死了（可能 GC 未完成）— 用 continue 保住循环，
                // deinit 会真正 cancel 这个 task，届时 for-await 会因 Cancellation 自然退出。
                // 若改成 return 一旦 self 短暂 nil 就永久丢续费/退款事件，漏钱风险。
                if case .verified(let tx) = result { await tx.finish() }
                await self?.refreshStatus()
            }
        }
    }
}

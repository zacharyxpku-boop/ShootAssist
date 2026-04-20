import UIKit

// MARK: - 姿势卡片渲染器
//
// 把一条 PosePreset + 当前机器邀请码渲染成 1080x1350（小红书 4:5 竖版）PNG。
// 用户在姿势详情 sheet 里点「分享这个姿势」→ 本渲染器产图 → ShareSheet 分享。
// 每张被分享的卡 = 一个获客入口：看到卡片的朋友扫码下载+填邀请码双方解锁 7 天 Pro。
//
// 设计原则：
// - 纯 UIKit drawing，不依赖 SwiftUI 快照，离屏可调用，性能稳定
// - 配色统一用项目已有的暖粉系（#FFF5F7 底 / #FF5A7E 主 / #FF8C42 橙强调）
// - 三段式版面：顶部 pose 标题 180pt / 中部白卡 600pt / 底部引导 400pt
// - 字体全部 UIFont.systemFont，中文粗细区分靠 weight（.bold / .semibold / .regular）

enum PosePresetCardRenderer {

    // MARK: - Public

    static func render(preset: PosePreset, referralCode: String) -> UIImage? {
        let size = CGSize(width: 1080, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // 直接按 1080 物理像素出图，不再乘屏幕 scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let image = renderer.image { ctx in
            // 背景
            UIColor(hex: "FFF5F7").setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            drawHeader(in: CGRect(x: 0, y: 0, width: size.width, height: 180), preset: preset)
            drawCenterCard(in: CGRect(x: 60, y: 210, width: size.width - 120, height: 600), preset: preset)
            drawFooter(in: CGRect(x: 0, y: 860, width: size.width, height: 400), referralCode: referralCode)
            drawBrandWatermark(in: CGRect(x: 0, y: 1290, width: size.width, height: 40))
        }
        return image
    }

    // MARK: - Sections

    /// 顶部 180pt：120pt emoji + 32pt 粗体「同款 Pose · [name]」
    private static func drawHeader(in rect: CGRect, preset: PosePreset) {
        // emoji 居中，偏上
        let emoji = preset.sceneEmoji as NSString
        let emojiFont = UIFont.systemFont(ofSize: 96, weight: .regular) // emoji 96 已足够显眼
        let emojiSize = emoji.size(withAttributes: [.font: emojiFont])
        emoji.draw(
            at: CGPoint(
                x: rect.midX - emojiSize.width / 2,
                y: rect.minY + 30
            ),
            withAttributes: [.font: emojiFont]
        )

        // 标题行
        let title = "同款 Pose · \(preset.name)" as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: UIColor(hex: "2B1810")
        ]
        let titleSize = title.size(withAttributes: titleAttrs)
        title.draw(
            at: CGPoint(
                x: rect.midX - titleSize.width / 2,
                y: rect.minY + 30 + emojiSize.height + 4
            ),
            withAttributes: titleAttrs
        )
    }

    /// 中部白卡：场景 tag + description + 机位提示
    private static func drawCenterCard(in rect: CGRect, preset: PosePreset) {
        // 卡底
        let cardPath = UIBezierPath(roundedRect: rect, cornerRadius: 28)
        UIColor.white.setFill()
        cardPath.fill()
        UIColor(hex: "FFD4E0").setStroke()
        cardPath.lineWidth = 2
        cardPath.stroke()

        // 顶部：sceneEmoji + 分类名
        let tagText = "\(preset.sceneEmoji)  \(preset.category.rawValue)" as NSString
        let tagAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: UIColor(hex: "FF5A7E")
        ]
        let tagSize = tagText.size(withAttributes: tagAttrs)
        tagText.draw(
            at: CGPoint(x: rect.midX - tagSize.width / 2, y: rect.minY + 44),
            withAttributes: tagAttrs
        )

        // 分隔线
        let sepRect = CGRect(x: rect.minX + 80, y: rect.minY + 110, width: rect.width - 160, height: 2)
        UIColor(hex: "FFE5EC").setFill()
        UIBezierPath(rect: sepRect).fill()

        // description 24pt 居中自动换行
        let descStyle = NSMutableParagraphStyle()
        descStyle.alignment = .center
        descStyle.lineSpacing = 10
        let descAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 34, weight: .regular),
            .foregroundColor: UIColor(hex: "4A3A33"),
            .paragraphStyle: descStyle
        ]
        let descRect = CGRect(
            x: rect.minX + 50,
            y: rect.minY + 150,
            width: rect.width - 100,
            height: 280
        )
        (preset.description as NSString).draw(with: descRect, options: [.usesLineFragmentOrigin], attributes: descAttrs, context: nil)

        // 底部机位提示区块
        let hintBoxRect = CGRect(
            x: rect.minX + 40,
            y: rect.maxY - 150,
            width: rect.width - 80,
            height: 110
        )
        let hintBoxPath = UIBezierPath(roundedRect: hintBoxRect, cornerRadius: 18)
        UIColor(hex: "FFF0F5").setFill()
        hintBoxPath.fill()

        let hintLabel = "相机提示" as NSString
        let hintLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor(hex: "FF5A7E")
        ]
        hintLabel.draw(
            at: CGPoint(x: hintBoxRect.minX + 24, y: hintBoxRect.minY + 16),
            withAttributes: hintLabelAttrs
        )

        let orientationText = preset.orientation == .portrait ? "竖构图" : "横构图"
        let hintText = "\(preset.cameraHint)  ·  \(orientationText)" as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .regular),
            .foregroundColor: UIColor(hex: "4A3A33")
        ]
        let hintRect = CGRect(
            x: hintBoxRect.minX + 24,
            y: hintBoxRect.minY + 48,
            width: hintBoxRect.width - 48,
            height: hintBoxRect.height - 56
        )
        hintText.draw(with: hintRect, options: [.usesLineFragmentOrigin], attributes: hintAttrs, context: nil)
    }

    /// 底部 400pt 引导区：产品名 + 下载提示 + 邀请码
    private static func drawFooter(in rect: CGRect, referralCode: String) {
        // 产品线 26pt 粗体
        let appLine = "小白快拍 AI 帮你拍" as NSString
        let appAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 36, weight: .bold),
            .foregroundColor: UIColor(hex: "2B1810")
        ]
        let appSize = appLine.size(withAttributes: appAttrs)
        appLine.draw(
            at: CGPoint(x: rect.midX - appSize.width / 2, y: rect.minY + 30),
            withAttributes: appAttrs
        )

        // 下载提示 18pt 灰
        let dlLine = "扫码或搜「小白快拍」下载" as NSString
        let dlAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: UIColor(hex: "8A6F65")
        ]
        let dlSize = dlLine.size(withAttributes: dlAttrs)
        dlLine.draw(
            at: CGPoint(x: rect.midX - dlSize.width / 2, y: rect.minY + 90),
            withAttributes: dlAttrs
        )

        // 邀请码胶囊
        let codeLine = "填邀请码 \(referralCode) 双方解锁 7 天 Pro" as NSString
        let codeAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 28, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let codeSize = codeLine.size(withAttributes: codeAttrs)
        let capsulePadX: CGFloat = 40
        let capsulePadY: CGFloat = 22
        let capsuleRect = CGRect(
            x: rect.midX - codeSize.width / 2 - capsulePadX,
            y: rect.minY + 170,
            width: codeSize.width + capsulePadX * 2,
            height: codeSize.height + capsulePadY * 2
        )
        let capsulePath = UIBezierPath(roundedRect: capsuleRect, cornerRadius: capsuleRect.height / 2)
        UIColor(hex: "FF8C42").setFill()
        capsulePath.fill()
        codeLine.draw(
            at: CGPoint(x: capsuleRect.minX + capsulePadX, y: capsuleRect.minY + capsulePadY),
            withAttributes: codeAttrs
        )

        // 引导小字
        let hint = "打开 App 填入上方邀请码即可双方解锁" as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 20, weight: .regular),
            .foregroundColor: UIColor(hex: "A0877D")
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        hint.draw(
            at: CGPoint(x: rect.midX - hintSize.width / 2, y: capsuleRect.maxY + 30),
            withAttributes: hintAttrs
        )
    }

    /// 底部品牌小字
    private static func drawBrandWatermark(in rect: CGRect) {
        let brand = "ShootAssist · 小白快拍" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: UIColor(hex: "C9AFA6")
        ]
        let size = brand.size(withAttributes: attrs)
        brand.draw(
            at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
            withAttributes: attrs
        )
    }
}

// MARK: - UIColor hex helper（若项目已有同名 extension，Swift 会选择先声明的；重复声明会报错，这里保护下）
#if !SHOOTASSIST_HAS_UICOLOR_HEX
private extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255
        let b = CGFloat(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}
#endif

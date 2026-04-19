import UIKit

// MARK: - 拍同款对比拼图生成
// 用于拍同款完成后，自动合成「参考图 | 你拍的」左右对比卡 + 匹配度 + 水印

class ComparisonCardService {
    static let shared = ComparisonCardService()
    private init() {}

    /// 生成对比拼图
    /// - Parameters:
    ///   - reference: 参考图（左）
    ///   - captured: 用户拍摄图（右）
    ///   - score: 匹配度 0-100
    /// - Returns: 合成后的 UIImage
    func generate(reference: UIImage, captured: UIImage, score: Int) -> UIImage {
        let cardW: CGFloat = 900
        let photoH: CGFloat = 600
        let footerH: CGFloat = 90
        let totalSize = CGSize(width: cardW, height: photoH + footerH)
        let halfW = cardW / 2

        let renderer = UIGraphicsImageRenderer(size: totalSize)
        return renderer.image { ctx in
            let cgCtx = ctx.cgContext

            // MARK: 背景
            UIColor(red: 0.99, green: 0.96, blue: 0.95, alpha: 1).setFill()
            UIRectFill(CGRect(origin: .zero, size: totalSize))

            // MARK: 左图（参考图）
            drawPhoto(reference, in: CGRect(x: 0, y: 0, width: halfW - 1, height: photoH), cgCtx: cgCtx)

            // MARK: 分割线
            UIColor.white.setFill()
            UIRectFill(CGRect(x: halfW - 1, y: 0, width: 2, height: photoH))

            // MARK: 右图（拍的）
            drawPhoto(captured, in: CGRect(x: halfW + 1, y: 0, width: halfW - 1, height: photoH), cgCtx: cgCtx)

            // MARK: 左上角标签
            drawLabel("参考图", in: CGRect(x: 10, y: 10, width: 70, height: 26), bgColor: UIColor.black.withAlphaComponent(0.5))
            drawLabel("你拍的", in: CGRect(x: halfW + 10, y: 10, width: 70, height: 26), bgColor: UIColor(red: 0.93, green: 0.33, blue: 0.49, alpha: 0.85))

            // MARK: Footer 背景
            let footerRect = CGRect(x: 0, y: photoH, width: cardW, height: footerH)
            UIColor.white.setFill()
            UIRectFill(footerRect)

            // Footer 顶部细线
            UIColor(red: 0.93, green: 0.33, blue: 0.49, alpha: 0.2).setFill()
            UIRectFill(CGRect(x: 0, y: photoH, width: cardW, height: 1.5))

            // MARK: 匹配度文字
            let scoreText = "匹配度 \(score)%  ✦  用小白快门拍的同款"
            let scoreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(red: 0.24, green: 0.16, blue: 0.18, alpha: 1)
            ]
            let scoreSize = (scoreText as NSString).size(withAttributes: scoreAttrs)
            let scoreX = (cardW - scoreSize.width) / 2
            (scoreText as NSString).draw(at: CGPoint(x: scoreX, y: photoH + 16), withAttributes: scoreAttrs)

            // MARK: 品牌水印 + 邀请码（小红书看到图就能截图记下邀请码进来）
            let code = ReferralManager.getReferralCode()
            let brandText = "小白快门 App  ·  邀请码 \(code)"
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: UIColor(red: 0.54, green: 0.43, blue: 0.46, alpha: 0.9)
            ]
            let brandSize = (brandText as NSString).size(withAttributes: brandAttrs)
            let brandX = (cardW - brandSize.width) / 2
            (brandText as NSString).draw(at: CGPoint(x: brandX, y: photoH + 50), withAttributes: brandAttrs)
        }
    }

    // MARK: - 辅助：填充绘制图片（aspectFill）

    private func drawPhoto(_ image: UIImage, in rect: CGRect, cgCtx: CGContext) {
        cgCtx.saveGState()
        UIBezierPath(rect: rect).addClip()

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawW = image.size.width * scale
        let drawH = image.size.height * scale
        let drawX = rect.minX + (rect.width - drawW) / 2
        let drawY = rect.minY + (rect.height - drawH) / 2

        image.draw(in: CGRect(x: drawX, y: drawY, width: drawW, height: drawH))
        cgCtx.restoreGState()
    }

    // MARK: - 辅助：圆角标签

    private func drawLabel(_ text: String, in rect: CGRect, bgColor: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2)
        bgColor.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = rect.minX + (rect.width - size.width) / 2
        let y = rect.minY + (rect.height - size.height) / 2
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
    }
}

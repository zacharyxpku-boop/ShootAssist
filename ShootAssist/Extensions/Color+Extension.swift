import SwiftUI

extension Color {
    // MARK: - 主色彩系统

    /// 暖米白 - 主页背景、整体底色
    static let warmCream = Color(hex: "FFF8F0")
    /// 温白 - 卡片背景、内容区域
    static let softWhite = Color(hex: "FFFAF5")
    /// 浅樱粉 - 边框线、浅色装饰
    static let sakuraPink = Color(hex: "FFD6E7")
    /// 蜜桃粉 - 辅助强调色、箭头
    static let peachPink = Color(hex: "FFB3CC")
    /// 玫瑰粉 - 主按钮、图标、强调元素
    static let rosePink = Color(hex: "FF85A1")
    /// 深玫红 - 标题文字、重要徽章
    static let deepRose = Color(hex: "E8637A")
    /// 暖蜜橙 - 视频模式配色点缀
    static let honeyOrange = Color(hex: "FFCBA4")
    /// 深莓棕 - 正文主文字
    static let berryBrown = Color(hex: "3D2C35")
    /// 中莓棕 - 次要说明文字
    static let midBerryBrown = Color(hex: "7A5C65")
    /// 浅粉 - 背景渐变
    static let lightPink = Color(hex: "FFE8F0")
    /// 淡紫粉 - 背景渐变
    static let lavenderPink = Color(hex: "FFF0FA")
    /// 浅色文字
    static let paleRose = Color(hex: "B89AA0")

    // MARK: - Hex 初始化

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

import Foundation

// MARK: - 爆款 Pose 数据库
//
// 基于小红书 2024-2026 真实搜索热度的 6 大场景 × 5 条结构化 Pose 库。
// 不走现有 PoseDatabase.swift（那套是视图层的扁平 40+ 泛用列表），
// 这份用于未来引导拍摄 / Pose 匹配场景推荐，在线跑 VisionService 匹配，
// 所以只存文字描述 + 拍摄提示，不写任何无法验证的骨骼坐标。
//
// 命名说明：现有 Resources/PoseDatabase.swift 里已有 struct PoseCategory，
// 为避免同 module 命名冲突，本文件枚举改名 PopularPoseCategory。

// MARK: - 构图方向
enum PoseOrientation {
    case portrait    // 竖构图
    case landscape   // 横构图
}

// MARK: - 场景分类
enum PopularPoseCategory: String, CaseIterable {
    case cafe           = "咖啡馆·文艺"
    case streetFashion  = "街拍·穿搭"
    case travel         = "出游·打卡"
    case couple         = "情侣·闺蜜"
    case home           = "家居·日常"
    case night          = "夜景·派对"

    var emoji: String {
        switch self {
        case .cafe:          return "☕"
        case .streetFashion: return "👗"
        case .travel:        return "🌊"
        case .couple:        return "💞"
        case .home:          return "🏠"
        case .night:         return "🌃"
        }
    }
}

// MARK: - 单条 Pose 预设
struct PosePreset: Identifiable, Hashable {
    let id: String
    let name: String              // 中文名，≤ 6 字
    let sceneEmoji: String        // 场景标记
    let description: String       // 一句话动作描述
    let orientation: PoseOrientation
    let cameraHint: String        // 相机参数建议
    let category: PopularPoseCategory
}

// MARK: - 30 条爆款 Pose 库
struct PopularPosePresets {

    static let all: [PosePreset] = [

        // ─────────────────────────────────────────
        // ☕ 咖啡馆·文艺（咖啡馆 / 书店 / 民宿）
        // ─────────────────────────────────────────
        PosePreset(
            id: "cafe_01",
            name: "托腮看窗外",
            sceneEmoji: "☕",
            description: "单手托腮侧坐靠窗，视线落在窗外，不看镜头",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 靠近对焦脸部，虚化窗外",
            category: .cafe
        ),
        PosePreset(
            id: "cafe_02",
            name: "端杯遮半脸",
            sceneEmoji: "☕",
            description: "双手端起咖啡杯，杯口挡住嘴和下巴，只露眼睛",
            orientation: .portrait,
            cameraHint: "竖构图 · 微俯 10° · 对焦眼睛",
            category: .cafe
        ),
        PosePreset(
            id: "cafe_03",
            name: "翻书低头",
            sceneEmoji: "📖",
            description: "双手捧书轻低头，头发自然垂下，侧身 45 度",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 逆光或侧光更文艺",
            category: .cafe
        ),
        PosePreset(
            id: "cafe_04",
            name: "桌面俯拍手",
            sceneEmoji: "🫖",
            description: "只拍桌面，手握杯柄入镜，不露脸",
            orientation: .landscape,
            cameraHint: "横构图 · 俯拍 90° · 桌面留白 1/3",
            category: .cafe
        ),
        PosePreset(
            id: "cafe_05",
            name: "假装看远方",
            sceneEmoji: "☕",
            description: "坐姿放松，一手搭膝一手扶杯，眼神飘向远处",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 用连拍抓自然表情",
            category: .cafe
        ),

        // ─────────────────────────────────────────
        // 👗 街拍·穿搭（街头 / 商场 / CBD 玻璃幕墙）
        // ─────────────────────────────────────────
        PosePreset(
            id: "street_01",
            name: "走路回头",
            sceneEmoji: "🚶‍♀️",
            description: "自然往前走，走两步回头看镜头一眼",
            orientation: .portrait,
            cameraHint: "竖构图 · 微仰 5° · 连拍模式",
            category: .streetFashion
        ),
        PosePreset(
            id: "street_02",
            name: "抓衣角",
            sceneEmoji: "👗",
            description: "单手轻轻拉起裙摆或外套下摆，身体微侧",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 全身入镜，露鞋",
            category: .streetFashion
        ),
        PosePreset(
            id: "street_03",
            name: "玻璃幕墙倒影",
            sceneEmoji: "🏙️",
            description: "侧身站在玻璃幕墙前，一半人一半倒影",
            orientation: .portrait,
            cameraHint: "竖构图 · 低角度向上 · 人占画面 1/2",
            category: .streetFashion
        ),
        PosePreset(
            id: "street_04",
            name: "低头摸头发",
            sceneEmoji: "💇‍♀️",
            description: "一只手拨耳后头发，头微低，脸侧 45 度",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 半身特写",
            category: .streetFashion
        ),
        PosePreset(
            id: "street_05",
            name: "插兜侧靠",
            sceneEmoji: "🧥",
            description: "双手插裤兜，身体靠墙或斜倚柱子，腿一前一后",
            orientation: .portrait,
            cameraHint: "竖构图 · 微仰 5° · 低角度显腿长",
            category: .streetFashion
        ),

        // ─────────────────────────────────────────
        // 🌊 出游·打卡（海边 / 山顶 / 景区地标）
        // ─────────────────────────────────────────
        PosePreset(
            id: "travel_01",
            name: "张开双臂",
            sceneEmoji: "🌊",
            description: "背对镜头面朝风景，双臂向两侧自然张开",
            orientation: .landscape,
            cameraHint: "横构图 · 平视或微仰 · 人物偏左或右 1/3",
            category: .travel
        ),
        PosePreset(
            id: "travel_02",
            name: "帽檐压低",
            sceneEmoji: "🧢",
            description: "一只手压住帽檐，脸藏一半，嘴角轻扬",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 脸部特写，天空当背景",
            category: .travel
        ),
        PosePreset(
            id: "travel_03",
            name: "地标小人",
            sceneEmoji: "🗼",
            description: "站在地标前很远处，人只占画面 1/5，突出场景",
            orientation: .landscape,
            cameraHint: "横构图 · 平视 · 大广角，地标完整入框",
            category: .travel
        ),
        PosePreset(
            id: "travel_04",
            name: "坐地远眺",
            sceneEmoji: "⛰️",
            description: "坐在山顶/栈道边缘，侧身看风景，膝盖收一只",
            orientation: .landscape,
            cameraHint: "横构图 · 低角度向上拍 · 人压画面下 1/3",
            category: .travel
        ),
        PosePreset(
            id: "travel_05",
            name: "牵裙奔跑",
            sceneEmoji: "👒",
            description: "单手提起裙摆/外套，朝镜头奔跑或回头笑",
            orientation: .landscape,
            cameraHint: "横构图 · 平视 · 高速连拍抓跳跃瞬间",
            category: .travel
        ),

        // ─────────────────────────────────────────
        // 💞 情侣·闺蜜（双人互动）
        // ─────────────────────────────────────────
        PosePreset(
            id: "couple_01",
            name: "额头相抵",
            sceneEmoji: "💑",
            description: "两人面对面额头轻碰，闭眼微笑",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视或微俯 · 特写上半身",
            category: .couple
        ),
        PosePreset(
            id: "couple_02",
            name: "牵手背影",
            sceneEmoji: "🤝",
            description: "两人牵手向前走，拍摄者从背后拍",
            orientation: .landscape,
            cameraHint: "横构图 · 低角度向上 · 脚步入画",
            category: .couple
        ),
        PosePreset(
            id: "couple_03",
            name: "比心手拼",
            sceneEmoji: "💕",
            description: "两人各伸一只手拼成爱心，贴近相机",
            orientation: .landscape,
            cameraHint: "横构图 · 平视 · 手在前脸在后虚化",
            category: .couple
        ),
        PosePreset(
            id: "couple_04",
            name: "耳语侧靠",
            sceneEmoji: "👯‍♀️",
            description: "一人凑到另一人耳边说话，另一人大笑",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 连拍抓自然笑容",
            category: .couple
        ),
        PosePreset(
            id: "couple_05",
            name: "并肩同框",
            sceneEmoji: "👭",
            description: "两人并肩站立，同时看向远方或镜头",
            orientation: .portrait,
            cameraHint: "竖构图 · 微仰 5° · 上半身入镜",
            category: .couple
        ),

        // ─────────────────────────────────────────
        // 🏠 家居·日常（房间 / 窗边 / 镜子前）
        // ─────────────────────────────────────────
        PosePreset(
            id: "home_01",
            name: "镜子半脸杀",
            sceneEmoji: "🪞",
            description: "举手机对镜拍，手机挡住半张脸，只露一只眼",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 对焦眼睛，背景干净",
            category: .home
        ),
        PosePreset(
            id: "home_02",
            name: "窗边逆光",
            sceneEmoji: "🪟",
            description: "侧坐窗台，阳光打在侧脸，低头看手或书",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 点测光对脸部，不要过曝",
            category: .home
        ),
        PosePreset(
            id: "home_03",
            name: "床上躺拍",
            sceneEmoji: "🛏️",
            description: "侧躺床上，手撑头，另一只手自然搭腰",
            orientation: .landscape,
            cameraHint: "横构图 · 微俯 15° · 从床头方向拍",
            category: .home
        ),
        PosePreset(
            id: "home_04",
            name: "地毯盘腿",
            sceneEmoji: "🧶",
            description: "盘腿坐地毯上，手捧热饮或书，低头轻笑",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视或微俯 · 全身入镜",
            category: .home
        ),
        PosePreset(
            id: "home_05",
            name: "浴室镜前",
            sceneEmoji: "💄",
            description: "对浴室镜抬头 45 度，手轻拨头发，不看镜头",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 镜面清洁干净",
            category: .home
        ),

        // ─────────────────────────────────────────
        // 🌃 夜景·派对（霓虹 / 酒吧 / 生日）
        // ─────────────────────────────────────────
        PosePreset(
            id: "night_01",
            name: "霓虹侧脸",
            sceneEmoji: "🌈",
            description: "站在霓虹灯牌侧面，让光打在脸颊上",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · ISO 调高，别开闪光",
            category: .night
        ),
        PosePreset(
            id: "night_02",
            name: "举杯干杯",
            sceneEmoji: "🍸",
            description: "举起酒杯到眼前，镜头对焦杯子，人虚化",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 大光圈，杯子入近景",
            category: .night
        ),
        PosePreset(
            id: "night_03",
            name: "蛋糕吹蜡烛",
            sceneEmoji: "🎂",
            description: "低头噘嘴对蛋糕蜡烛，眼睛朝上瞥镜头",
            orientation: .portrait,
            cameraHint: "竖构图 · 微俯 15° · 蜡烛光当主光源",
            category: .night
        ),
        PosePreset(
            id: "night_04",
            name: "人群剪影",
            sceneEmoji: "🎉",
            description: "背对镜头举起双手，融入人群和舞台灯光",
            orientation: .landscape,
            cameraHint: "横构图 · 微仰 · 剪影压画面 1/3",
            category: .night
        ),
        PosePreset(
            id: "night_05",
            name: "仙女棒甩光",
            sceneEmoji: "✨",
            description: "手握仙女棒画圈或写字，脸被光轨照亮",
            orientation: .portrait,
            cameraHint: "竖构图 · 平视 · 慢门 1-2 秒",
            category: .night
        ),
    ]

    /// 按场景分类筛选
    static func by(category: PopularPoseCategory) -> [PosePreset] {
        all.filter { $0.category == category }
    }
}

import Foundation

// MARK: - Pose 数据模型
struct PoseData: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let tips: [String]
    let difficulty: Int         // 1-3
    let bestFor: String
    let cameraAngle: String
    let icon: String            // SF Symbol name (使用 iOS 16 兼容的符号)
}

struct PoseCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let poses: [PoseData]
}

// MARK: - 预设 Pose 库（8 类 40+ 个 Pose）
let poseDatabase: [PoseCategory] = [
    PoseCategory(name: "半身照", icon: "🤳", poses: [
        PoseData(name: "正面微笑", description: "面对镜头，嘴角自然上扬", tips: ["下巴微收", "眼睛看镜头上方一点", "肩膀放松别耸"], difficulty: 1, bestFor: "社交头像、证件照", cameraAngle: "平视", icon: "face.smiling"),
        PoseData(name: "侧脸45度", description: "脸侧向一边约45度，展示轮廓", tips: ["靠近镜头的眼睛稍微看镜头", "下颌线要清晰", "可以用手轻托下巴"], difficulty: 1, bestFor: "自拍、朋友圈", cameraAngle: "平视或微俯", icon: "person.fill"),
        PoseData(name: "手托下巴", description: "单手轻托下巴，显脸小", tips: ["手指自然弯曲", "别用力压脸", "眼神看远处更有意境"], difficulty: 1, bestFor: "咖啡厅、餐厅", cameraAngle: "平视", icon: "hand.raised"),
        PoseData(name: "撩头发", description: "一只手撩起耳边头发", tips: ["动作要慢，用连拍抓", "眼睛可以微闭", "笑容自然最好看"], difficulty: 2, bestFor: "户外、逆光", cameraAngle: "微仰10°", icon: "wind"),
        PoseData(name: "叉腰自信", description: "单手或双手叉腰", tips: ["手肘往后推，显腰细", "身体微侧", "挺胸收腹"], difficulty: 1, bestFor: "穿搭展示", cameraAngle: "平视", icon: "figure.arms.open"),
    ]),
    PoseCategory(name: "全身照", icon: "🧍‍♀️", poses: [
        PoseData(name: "走路抓拍", description: "自然走路，用连拍捕捉", tips: ["大步走，手臂自然摆", "看远处，别看镜头", "身体微侧最好看"], difficulty: 2, bestFor: "街拍、旅行", cameraAngle: "微仰5°", icon: "figure.walk"),
        PoseData(name: "靠墙单脚", description: "背靠墙壁，一只脚弯曲踩墙", tips: ["头微微靠墙", "插口袋或抱胸都OK", "目光看远方"], difficulty: 1, bestFor: "街拍、建筑前", cameraAngle: "微仰5°", icon: "figure.stand"),
        PoseData(name: "回头看", description: "背对镜头走，然后回头", tips: ["回头时眼神找镜头", "用连拍抓最佳瞬间", "头发飘起来加分"], difficulty: 2, bestFor: "户外、花丛", cameraAngle: "平视", icon: "arrow.turn.up.left"),
        PoseData(name: "坐台阶", description: "坐在台阶上，腿自然伸展", tips: ["坐1/3位置，别坐满", "一条腿弯曲一条伸直", "身体微微前倾"], difficulty: 1, bestFor: "校园、公园", cameraAngle: "微俯15°", icon: "figure.roll"),
        PoseData(name: "背影照", description: "背对镜头，展示穿搭或风景", tips: ["稍微侧身更好看", "头可以微转", "手可以拿帽子/包包"], difficulty: 1, bestFor: "风景、穿搭", cameraAngle: "平视", icon: "figure.walk.departure"),
    ]),
    PoseCategory(name: "情侣照", icon: "💑", poses: [
        PoseData(name: "额头相贴", description: "两人额头轻轻靠在一起", tips: ["双方都闭眼最甜", "微微笑", "手牵着或搂腰"], difficulty: 1, bestFor: "纪念日、旅行", cameraAngle: "微俯", icon: "heart.fill"),
        PoseData(name: "牵手走", description: "两人牵手往前走", tips: ["走路步幅一致", "可以互看对方笑", "用连拍"], difficulty: 2, bestFor: "海边、公园", cameraAngle: "平视", icon: "figure.2.and.child.holdinghands"),
        PoseData(name: "背靠背", description: "两人背对背站立", tips: ["可以双手交叉抱胸", "表情看各自的远方", "有默契感更好看"], difficulty: 1, bestFor: "校园、街拍", cameraAngle: "平视或微仰", icon: "person.2"),
        PoseData(name: "公主抱", description: "一人抱起另一人", tips: ["被抱的人搂住脖子", "抱的人别太僵硬", "连拍选最自然的"], difficulty: 3, bestFor: "婚纱、纪念", cameraAngle: "微仰", icon: "figure.2.arms.open"),
    ]),
    PoseCategory(name: "闺蜜照", icon: "👯‍♀️", poses: [
        PoseData(name: "勾肩搭背", description: "互相搂肩膀", tips: ["身高差大的可以歪头", "表情越夸张越好玩", "腿可以交叉站"], difficulty: 1, bestFor: "出游、聚会", cameraAngle: "平视", icon: "person.2.fill"),
        PoseData(name: "比心合照", description: "两人各出一只手组成心形", tips: ["手要贴紧", "可以用大心或小心", "笑得灿烂一点"], difficulty: 1, bestFor: "合影", cameraAngle: "平视", icon: "heart"),
        PoseData(name: "跳跃定格", description: "一起跳起来", tips: ["数到三一起跳", "用连拍", "表情越搞怪越好"], difficulty: 3, bestFor: "海边、草地", cameraAngle: "微仰", icon: "figure.walk"),
        PoseData(name: "回头对视", description: "并排站，同时回头看镜头", tips: ["保持一定距离", "一人笑一人酷", "头发飘起加分"], difficulty: 2, bestFor: "街拍", cameraAngle: "跟拍", icon: "arrow.turn.up.left"),
    ]),
    PoseCategory(name: "美食", icon: "🍰", poses: [
        PoseData(name: "举起美食", description: "将食物举到脸旁", tips: ["食物靠近脸但别挡脸", "表情要馋", "背景简洁"], difficulty: 1, bestFor: "探店、美食分享", cameraAngle: "微俯15°", icon: "fork.knife"),
        PoseData(name: "假装吃", description: "叉子/筷子送到嘴边", tips: ["嘴巴微张", "眼睛看食物", "手的姿势要优雅"], difficulty: 1, bestFor: "餐厅", cameraAngle: "平视", icon: "fork.knife"),
        PoseData(name: "俯拍摆盘", description: "从正上方拍桌面上的食物", tips: ["盘子周围放装饰", "手可以入镜", "光线要亮"], difficulty: 1, bestFor: "下午茶、早餐", cameraAngle: "俯拍90°", icon: "camera.viewfinder"),
    ]),
    PoseCategory(name: "街拍", icon: "🏙️", poses: [
        PoseData(name: "走斑马线", description: "走在斑马线上回头", tips: ["走在线中间", "步伐大一点", "连拍抓拍"], difficulty: 2, bestFor: "城市街拍", cameraAngle: "微仰", icon: "road.lanes"),
        PoseData(name: "橱窗前", description: "站在好看的橱窗/涂鸦墙前", tips: ["身体微侧", "可以看橱窗不看镜头", "跟背景颜色呼应"], difficulty: 1, bestFor: "逛街、旅行", cameraAngle: "平视", icon: "storefront"),
        PoseData(name: "地铁扶杆", description: "扶着地铁杆，微微倾斜", tips: ["单手扶杆", "身体重心往后", "表情放空"], difficulty: 2, bestFor: "日常记录", cameraAngle: "平视", icon: "tram"),
    ]),
    PoseCategory(name: "旅行", icon: "✈️", poses: [
        PoseData(name: "比耶打卡", description: "在地标前比耶", tips: ["地标放在身后", "别挡住景点", "微笑最自然"], difficulty: 1, bestFor: "景点打卡", cameraAngle: "微仰", icon: "hand.raised"),
        PoseData(name: "远眺风景", description: "侧身看远方", tips: ["只露侧脸", "风吹头发更好", "手可以放在栏杆上"], difficulty: 1, bestFor: "山顶、海边", cameraAngle: "侧面平视", icon: "binoculars"),
        PoseData(name: "行李箱合照", description: "拉着行李箱回头", tips: ["行李箱颜色鲜艳加分", "穿搭和场景呼应", "机场/车站最经典"], difficulty: 1, bestFor: "出发/到达", cameraAngle: "平视", icon: "suitcase.rolling"),
    ]),
    PoseCategory(name: "自拍技巧", icon: "🤳", poses: [
        PoseData(name: "45度俯拍", description: "手机举高45度角俯拍", tips: ["下巴微收", "眼睛往上看镜头", "这个角度显脸最小"], difficulty: 1, bestFor: "任何场景自拍", cameraAngle: "俯拍45°", icon: "iphone"),
        PoseData(name: "侧脸自拍", description: "侧脸对镜头，另一只手托腮", tips: ["找到自己好看的那一侧", "光打在脸的正面", "表情自然"], difficulty: 1, bestFor: "日常自拍", cameraAngle: "平视侧面", icon: "person.crop.circle"),
        PoseData(name: "镜子自拍", description: "对着镜子拍", tips: ["镜子要干净", "手机别挡脸", "背景整洁"], difficulty: 1, bestFor: "穿搭展示", cameraAngle: "平视", icon: "rectangle.portrait.and.arrow.right"),
    ]),
]

// MARK: - 拍照小技巧
let photoTips: [String] = [
    "手机放在胸口高度拍半身照，显脸小",
    "逆光拍剪影，侧光拍轮廓",
    "45度侧脸是最万能的角度",
    "手别放在身体两侧——叉腰或摸头发",
    "拍全身照时手机放低，腿会显长",
    "背景越简洁，主体越突出",
    "自然光永远是最好的灯光",
    "拍集体照让最高的站中间",
    "连拍10张选1张，比摆1张好",
    "走路抓拍比站着摆pose更自然",
]

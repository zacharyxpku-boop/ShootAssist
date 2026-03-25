import Foundation

// MARK: - 内置 Demo 模板（免费用户可直接体验，无需导入视频）

struct DemoEntry: Identifiable {
    let id = UUID()
    let name: String
    let icon: String           // emoji icon for the card
    let description: String
    let durationLabel: String
    let template: AnalyzedTemplate
}

let demoTemplates: [DemoEntry] = [

    // Demo 1：比心舞（经典，简单好跟）
    DemoEntry(
        name: "比心舞",
        icon: "🫶",
        description: "经典比心手势，简单好跟",
        durationLabel: "9s",
        template: AnalyzedTemplate(
            audioURL: nil,
            emojiMoves: [
                EmojiMove(timestamp: 0.5,  emoji: "🤸", description: "展开双臂"),
                EmojiMove(timestamp: 1.5,  emoji: "🫶", description: "比心"),
                EmojiMove(timestamp: 2.5,  emoji: "☝️", description: "指天"),
                EmojiMove(timestamp: 3.5,  emoji: "🫶", description: "比心"),
                EmojiMove(timestamp: 4.5,  emoji: "🙌", description: "双手举高"),
                EmojiMove(timestamp: 5.5,  emoji: "🫶", description: "比心"),
                EmojiMove(timestamp: 6.5,  emoji: "😘", description: "飞吻"),
                EmojiMove(timestamp: 7.5,  emoji: "🫶", description: "比心"),
            ],
            duration: 9.0
        )
    ),

    // Demo 2：卖萌舞（撒娇感，适合短视频）
    DemoEntry(
        name: "卖萌舞",
        icon: "🤭",
        description: "撒娇卖萌，超适合发小红书",
        durationLabel: "10s",
        template: AnalyzedTemplate(
            audioURL: nil,
            emojiMoves: [
                EmojiMove(timestamp: 0.5,  emoji: "🤭", description: "捂脸卖萌"),
                EmojiMove(timestamp: 1.8,  emoji: "😘", description: "飞吻"),
                EmojiMove(timestamp: 3.0,  emoji: "🤭", description: "捂脸卖萌"),
                EmojiMove(timestamp: 4.2,  emoji: "🫶", description: "比心"),
                EmojiMove(timestamp: 5.4,  emoji: "🤔", description: "托腮"),
                EmojiMove(timestamp: 6.6,  emoji: "🤭", description: "捂脸卖萌"),
                EmojiMove(timestamp: 7.8,  emoji: "😘", description: "飞吻"),
            ],
            duration: 9.5
        )
    ),

    // Demo 3：能量舞（高燃，适合运动/出游）
    DemoEntry(
        name: "能量舞",
        icon: "🙌",
        description: "高能量，举手加油超燃",
        durationLabel: "8s",
        template: AnalyzedTemplate(
            audioURL: nil,
            emojiMoves: [
                EmojiMove(timestamp: 0.4,  emoji: "🙌", description: "双手举高"),
                EmojiMove(timestamp: 1.2,  emoji: "🤸", description: "展开双臂"),
                EmojiMove(timestamp: 2.0,  emoji: "🙌", description: "双手举高"),
                EmojiMove(timestamp: 2.8,  emoji: "☝️", description: "指天"),
                EmojiMove(timestamp: 3.6,  emoji: "👏", description: "拍手"),
                EmojiMove(timestamp: 4.4,  emoji: "🙌", description: "双手举高"),
                EmojiMove(timestamp: 5.2,  emoji: "🤸", description: "展开双臂"),
                EmojiMove(timestamp: 6.0,  emoji: "🙌", description: "双手举高"),
                EmojiMove(timestamp: 6.8,  emoji: "☝️", description: "指天"),
            ],
            duration: 8.0
        )
    )
]

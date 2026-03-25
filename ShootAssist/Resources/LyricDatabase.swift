import Foundation

// MARK: - 歌词行（带时间轴）
struct LyricLine: Identifiable {
    let id = UUID()
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

// MARK: - 歌曲歌词
struct SongLyrics: Identifiable {
    let id = UUID()
    let songName: String
    let artist: String
    let lines: [LyricLine]
}

// MARK: - 预设歌词库（带时间轴，第一版先做 5 首热门歌）
let lyricDatabase: [SongLyrics] = [
    SongLyrics(songName: "孤勇者", artist: "陈奕迅", lines: [
        LyricLine(text: "爱你孤身走暗巷 ♪", startTime: 0, endTime: 3.2),
        LyricLine(text: "爱你不跪的模样 ♪", startTime: 3.2, endTime: 6.1),
        LyricLine(text: "爱你对峙过绝望 ♪", startTime: 6.1, endTime: 9.0),
        LyricLine(text: "不肯哭一场 ♪", startTime: 9.0, endTime: 11.5),
        LyricLine(text: "爱你破烂的衣裳 ♪", startTime: 11.5, endTime: 14.5),
        LyricLine(text: "却敢堵命运的枪 ♪", startTime: 14.5, endTime: 17.5),
        LyricLine(text: "爱你和我那么像 ♪", startTime: 17.5, endTime: 20.5),
        LyricLine(text: "缺口都一样 ♪", startTime: 20.5, endTime: 23.0),
        LyricLine(text: "去吗 配吗 这褴褛的披风 ♪", startTime: 23.0, endTime: 27.0),
        LyricLine(text: "战吗 战啊 以最卑微的梦 ♪", startTime: 27.0, endTime: 31.0),
        LyricLine(text: "致那黑夜中的呜咽与怒吼 ♪", startTime: 31.0, endTime: 35.0),
        LyricLine(text: "谁说站在光里的才算英雄 ♪", startTime: 35.0, endTime: 39.0),
    ]),
    SongLyrics(songName: "七里香", artist: "周杰伦", lines: [
        LyricLine(text: "窗外的麻雀 在电线杆上多嘴 ♪", startTime: 0, endTime: 4.5),
        LyricLine(text: "你说这一句 很有夏天的感觉 ♪", startTime: 4.5, endTime: 9.0),
        LyricLine(text: "手中的铅笔 在纸上来来回回 ♪", startTime: 9.0, endTime: 13.5),
        LyricLine(text: "我用几行字形容你是我的谁 ♪", startTime: 13.5, endTime: 18.0),
        LyricLine(text: "秋刀鱼的滋味 猫跟你都想了解 ♪", startTime: 18.0, endTime: 22.5),
        LyricLine(text: "初恋的香味就这样被我们寻回 ♪", startTime: 22.5, endTime: 27.0),
        LyricLine(text: "雨下整夜 我的爱溢出就像雨水 ♪", startTime: 27.0, endTime: 32.0),
        LyricLine(text: "窗台蝴蝶 像诗里纷飞的美 ♪", startTime: 32.0, endTime: 36.0),
    ]),
    SongLyrics(songName: "晴天", artist: "周杰伦", lines: [
        LyricLine(text: "故事的小黄花 ♪", startTime: 0, endTime: 3.5),
        LyricLine(text: "从出生那年就飘着 ♪", startTime: 3.5, endTime: 7.0),
        LyricLine(text: "童年的荡秋千 ♪", startTime: 7.0, endTime: 10.5),
        LyricLine(text: "随记忆一直晃到现在 ♪", startTime: 10.5, endTime: 15.0),
        LyricLine(text: "刮风这天 我试过握着你手 ♪", startTime: 15.0, endTime: 20.0),
        LyricLine(text: "但偏偏 雨渐渐 大到我看你不见 ♪", startTime: 20.0, endTime: 25.0),
        LyricLine(text: "还要多久 我才能在你身边 ♪", startTime: 25.0, endTime: 30.0),
        LyricLine(text: "等到放晴的那天 也许我会比较好一点 ♪", startTime: 30.0, endTime: 36.0),
    ]),
    SongLyrics(songName: "起风了", artist: "买辣椒也用券", lines: [
        LyricLine(text: "这一路上走走停停 ♪", startTime: 0, endTime: 4.0),
        LyricLine(text: "顺着少年漂流的痕迹 ♪", startTime: 4.0, endTime: 8.0),
        LyricLine(text: "迈出车站的前一刻 ♪", startTime: 8.0, endTime: 12.0),
        LyricLine(text: "竟有些犹豫 ♪", startTime: 12.0, endTime: 15.0),
        LyricLine(text: "不禁笑这近乡情怯 ♪", startTime: 15.0, endTime: 19.0),
        LyricLine(text: "仍无可避免 ♪", startTime: 19.0, endTime: 22.0),
        LyricLine(text: "而长野的天 依旧那么暖 ♪", startTime: 22.0, endTime: 27.0),
        LyricLine(text: "风吹起了从前 ♪", startTime: 27.0, endTime: 31.0),
    ]),
    SongLyrics(songName: "向云端", artist: "小霞&海洋Bo", lines: [
        LyricLine(text: "我要去 去大理 去远方 ♪", startTime: 0, endTime: 4.0),
        LyricLine(text: "我要去 见苍山 洱海旁 ♪", startTime: 4.0, endTime: 8.0),
        LyricLine(text: "在路上 追赶着 那朝阳 ♪", startTime: 8.0, endTime: 12.0),
        LyricLine(text: "向云端 山那边 海里面 ♪", startTime: 12.0, endTime: 16.0),
        LyricLine(text: "有真实的世界 有梦的彼岸 ♪", startTime: 16.0, endTime: 21.0),
        LyricLine(text: "阳光温暖 快乐在身边 ♪", startTime: 21.0, endTime: 25.0),
        LyricLine(text: "不必流连 不必纠缠 ♪", startTime: 25.0, endTime: 29.0),
        LyricLine(text: "让笑容在心间绽放蔓延 ♪", startTime: 29.0, endTime: 34.0),
    ]),
]

// MARK: - 手势舞动作库
struct DanceMove: Identifiable {
    let id = UUID()
    let timestamp: TimeInterval
    let description: String
    let icon: String
}

struct DanceRoutine: Identifiable {
    let id = UUID()
    let name: String
    let moves: [DanceMove]
}

let danceLibrary: [DanceRoutine] = [
    DanceRoutine(name: "基础手势舞", moves: [
        DanceMove(timestamp: 0,    description: "双手比心",   icon: "🫶"),
        DanceMove(timestamp: 1.5,  description: "右手摆",     icon: "👋"),
        DanceMove(timestamp: 3.0,  description: "双手叉腰",   icon: "🤗"),
        DanceMove(timestamp: 4.5,  description: "左手指天",   icon: "☝️"),
        DanceMove(timestamp: 6.0,  description: "右手指前方", icon: "👉"),
        DanceMove(timestamp: 7.5,  description: "双手张开",   icon: "🤲"),
        DanceMove(timestamp: 9.0,  description: "拍手",       icon: "👏"),
        DanceMove(timestamp: 10.5, description: "比耶",       icon: "✌️"),
        DanceMove(timestamp: 12.0, description: "双手比心",   icon: "🫶"),
    ]),
    DanceRoutine(name: "抖音热门", moves: [
        DanceMove(timestamp: 0,    description: "双手交叉胸前", icon: "🙅"),
        DanceMove(timestamp: 1.2,  description: "打开双臂",     icon: "🤸"),
        DanceMove(timestamp: 2.4,  description: "右手摸头",     icon: "💆"),
        DanceMove(timestamp: 3.6,  description: "左右摆手",     icon: "🙌"),
        DanceMove(timestamp: 4.8,  description: "转圈指天",     icon: "💫"),
        DanceMove(timestamp: 6.0,  description: "比耶自拍",     icon: "🤳"),
        DanceMove(timestamp: 7.2,  description: "双手捧脸",     icon: "🥰"),
        DanceMove(timestamp: 8.4,  description: "抱拳",         icon: "🤜"),
        DanceMove(timestamp: 9.6,  description: "飞吻",         icon: "😘"),
        DanceMove(timestamp: 10.8, description: "双手比心",     icon: "🫶"),
    ]),
    DanceRoutine(name: "可爱风", moves: [
        DanceMove(timestamp: 0,    description: "歪头卖萌",     icon: "🥺"),
        DanceMove(timestamp: 1.5,  description: "双手比兔耳朵", icon: "🐰"),
        DanceMove(timestamp: 3.0,  description: "捂嘴偷笑",     icon: "🤭"),
        DanceMove(timestamp: 4.5,  description: "托腮思考",     icon: "🤔"),
        DanceMove(timestamp: 6.0,  description: "双手握拳加油", icon: "💪"),
        DanceMove(timestamp: 7.5,  description: "蒙眼睛偷看",   icon: "🙈"),
        DanceMove(timestamp: 9.0,  description: "双手飞吻",     icon: "💋"),
        DanceMove(timestamp: 10.5, description: "害羞捂脸",     icon: "😊"),
    ]),
    DanceRoutine(name: "元气节拍", moves: [
        DanceMove(timestamp: 0,    description: "双手举高欢呼", icon: "🙌"),
        DanceMove(timestamp: 1.0,  description: "叉腰扭动",     icon: "🕺"),
        DanceMove(timestamp: 2.0,  description: "左手拍肩",     icon: "💁"),
        DanceMove(timestamp: 3.0,  description: "双手交叉再开", icon: "🙆"),
        DanceMove(timestamp: 4.0,  description: "向前推掌",     icon: "🤚"),
        DanceMove(timestamp: 5.0,  description: "双手指天",     icon: "🫡"),
        DanceMove(timestamp: 6.0,  description: "左右侧摆",     icon: "🏄"),
        DanceMove(timestamp: 7.0,  description: "双手比心",     icon: "🫶"),
        DanceMove(timestamp: 8.0,  description: "360转圈",      icon: "🌀"),
        DanceMove(timestamp: 9.2,  description: "定格 ending",  icon: "⚡"),
    ]),
    DanceRoutine(name: "温柔慢舞", moves: [
        DanceMove(timestamp: 0,    description: "双臂缓缓展开", icon: "🕊️"),
        DanceMove(timestamp: 2.0,  description: "手轻抚脸颊",   icon: "🌸"),
        DanceMove(timestamp: 4.0,  description: "指尖向上漂移", icon: "✨"),
        DanceMove(timestamp: 6.0,  description: "双手环抱自己", icon: "🤗"),
        DanceMove(timestamp: 8.0,  description: "轻柔托腮",     icon: "🤔"),
        DanceMove(timestamp: 10.0, description: "手指飞吻",     icon: "😘"),
        DanceMove(timestamp: 12.0, description: "双手心形",     icon: "🫶"),
    ]),
    DanceRoutine(name: "炸场嘻哈", moves: [
        DanceMove(timestamp: 0,    description: "叉腰亮相",     icon: "😤"),
        DanceMove(timestamp: 0.8,  description: "比耶两连",     icon: "✌️"),
        DanceMove(timestamp: 1.6,  description: "抱拳出击",     icon: "🥊"),
        DanceMove(timestamp: 2.4,  description: "双手展开冲",   icon: "🤸"),
        DanceMove(timestamp: 3.2,  description: "举高 yeah",    icon: "🙌"),
        DanceMove(timestamp: 4.0,  description: "摸头炫酷",     icon: "😎"),
        DanceMove(timestamp: 4.8,  description: "指天宣告",     icon: "☝️"),
        DanceMove(timestamp: 5.6,  description: "飞吻收场",     icon: "😘"),
        DanceMove(timestamp: 6.4,  description: "大比心",       icon: "🫶"),
    ]),
]

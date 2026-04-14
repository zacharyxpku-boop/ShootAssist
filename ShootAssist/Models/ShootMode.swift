import Foundation

// MARK: - 照片子模式
enum PhotoSubMode: String, CaseIterable, Identifiable {
    case influencerClone  = "拍同款"
    case smartComposition = "智能构图"
    case cameraGuide      = "机位提示"

    var id: String { rawValue }
}

// MARK: - 延时选项
enum DelayOption: Int, CaseIterable {
    case none  = 0
    case three = 3
    case five  = 5
    case ten   = 10

    var label: String {
        switch self {
        case .none:  return "即时"
        case .three: return "3s"
        case .five:  return "5s"
        case .ten:   return "10s"
        }
    }
}

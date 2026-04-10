import UIKit
import Vision
import CoreImage

// MARK: - 光线检测结果
struct LightingResult: Equatable {
    let quality: LightingQuality
    let tips: [String]
    let faceBrightness: Float     // 0-1 脸部平均亮度
    let backgroundBrightness: Float // 0-1 背景平均亮度
    let leftRightRatio: Float     // 左右脸亮度比

    static let empty = LightingResult(
        quality: .unknown, tips: [], faceBrightness: 0,
        backgroundBrightness: 0, leftRightRatio: 1.0
    )
}

enum LightingQuality: String, Equatable {
    case good = "光线均匀"
    case backlit = "逆光"
    case harshSide = "侧光过强"
    case tooDark = "光线不足"
    case tooBright = "过度曝光"
    case unknown = "检测中"
}

// MARK: - 光线检测服务
class LightingDetectionService {

    private let ciContext = CIContext()

    /// 从 CVPixelBuffer + 人脸框分析光线质量
    func analyzeLighting(
        pixelBuffer: CVPixelBuffer,
        faceRect: CGRect?
    ) -> LightingResult {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageExtent = ciImage.extent

        // 全图平均亮度
        let overallBrightness = averageLuminance(ciImage, region: imageExtent)

        guard let face = faceRect, face.width > 0.01, face.height > 0.01 else {
            return classifyWithoutFace(overall: overallBrightness)
        }

        // 将 Vision 归一化坐标 → CIImage 像素坐标
        let facePixelRect = CGRect(
            x: face.minX * imageExtent.width,
            y: face.minY * imageExtent.height,
            width: face.width * imageExtent.width,
            height: face.height * imageExtent.height
        )

        let faceBrightness = averageLuminance(ciImage, region: facePixelRect)

        // 左右脸亮度对比
        let leftHalf = CGRect(
            x: facePixelRect.minX,
            y: facePixelRect.minY,
            width: facePixelRect.width / 2,
            height: facePixelRect.height
        )
        let rightHalf = CGRect(
            x: facePixelRect.midX,
            y: facePixelRect.minY,
            width: facePixelRect.width / 2,
            height: facePixelRect.height
        )
        let leftBrightness = averageLuminance(ciImage, region: leftHalf)
        let rightBrightness = averageLuminance(ciImage, region: rightHalf)

        let lrRatio: Float = min(leftBrightness, rightBrightness) > 0.01
            ? max(leftBrightness, rightBrightness) / min(leftBrightness, rightBrightness)
            : 1.0

        // 背景亮度（全图减去人脸区域的近似）
        let bgBrightness = overallBrightness

        return classify(
            face: faceBrightness,
            background: bgBrightness,
            lrRatio: lrRatio
        )
    }

    /// 从 UIImage 分析（静态图片用）
    func analyzeLighting(in image: UIImage, faceRect: CGRect?) -> LightingResult {
        guard let ciImage = CIImage(image: image) else {
            return .empty
        }
        let extent = ciImage.extent
        let overall = averageLuminance(ciImage, region: extent)

        guard let face = faceRect, face.width > 0.01 else {
            return classifyWithoutFace(overall: overall)
        }

        let facePixelRect = CGRect(
            x: face.minX * extent.width,
            y: face.minY * extent.height,
            width: face.width * extent.width,
            height: face.height * extent.height
        )
        let faceBrightness = averageLuminance(ciImage, region: facePixelRect)

        let leftHalf = CGRect(
            x: facePixelRect.minX, y: facePixelRect.minY,
            width: facePixelRect.width / 2, height: facePixelRect.height
        )
        let rightHalf = CGRect(
            x: facePixelRect.midX, y: facePixelRect.minY,
            width: facePixelRect.width / 2, height: facePixelRect.height
        )
        let leftB = averageLuminance(ciImage, region: leftHalf)
        let rightB = averageLuminance(ciImage, region: rightHalf)
        let lrRatio: Float = min(leftB, rightB) > 0.01
            ? max(leftB, rightB) / min(leftB, rightB) : 1.0

        return classify(face: faceBrightness, background: overall, lrRatio: lrRatio)
    }

    // MARK: - Private

    private func averageLuminance(_ image: CIImage, region: CGRect) -> Float {
        guard region.width > 0, region.height > 0 else { return 0 }
        let clampedRegion = region.intersection(image.extent)
        guard !clampedRegion.isEmpty else { return 0 }

        guard let filter = CIFilter(name: "CIAreaAverage") else { return 0 }
        filter.setValue(image.cropped(to: clampedRegion), forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: clampedRegion), forKey: "inputExtent")

        guard let outputImage = filter.outputImage else { return 0 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )

        // ITU-R BT.709 luminance
        let r = Float(bitmap[0]) / 255.0
        let g = Float(bitmap[1]) / 255.0
        let b = Float(bitmap[2]) / 255.0
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private func classify(face: Float, background: Float, lrRatio: Float) -> LightingResult {
        var tips: [String] = []
        let quality: LightingQuality

        if face < 0.15 {
            quality = .tooDark
            tips.append("光线太暗，找个亮一点的地方")
        } else if face > 0.85 {
            quality = .tooBright
            tips.append("过曝了，避开直射强光")
        } else if background > face * 1.8 && face < 0.4 {
            quality = .backlit
            tips.append("逆光了，转个方向让光照到脸上")
        } else if lrRatio > 1.6 {
            quality = .harshSide
            tips.append("一侧脸太暗，侧一下身让光线更均匀")
        } else {
            quality = .good
            tips.append("光线不错，可以拍了")
        }

        return LightingResult(
            quality: quality,
            tips: tips,
            faceBrightness: face,
            backgroundBrightness: background,
            leftRightRatio: lrRatio
        )
    }

    private func classifyWithoutFace(overall: Float) -> LightingResult {
        let quality: LightingQuality
        var tips: [String] = []

        if overall < 0.15 {
            quality = .tooDark
            tips.append("环境太暗，找个亮一点的地方")
        } else if overall > 0.85 {
            quality = .tooBright
            tips.append("环境过亮，避开直射强光")
        } else {
            quality = .good
            tips.append("环境光线OK")
        }

        return LightingResult(
            quality: quality, tips: tips,
            faceBrightness: overall, backgroundBrightness: overall,
            leftRightRatio: 1.0
        )
    }
}

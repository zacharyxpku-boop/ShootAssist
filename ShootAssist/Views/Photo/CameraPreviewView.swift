import SwiftUI
import AVFoundation

// MARK: - UIKit 相机预览层桥接
/// AVCaptureVideoPreviewLayer 对前置摄像头已自动镜像（automaticallyAdjustsVideoMirroring = true），
/// 无需手动 transform。保存的照片由 AVCapturePhotoOutput 输出正向数据，也无需额外处理。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// 点击回调：返回归一化坐标 (0...1)，用于对焦
    var onTapToFocus: ((CGPoint) -> Void)?

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        // .resizeAspectFill = 等比缩放填满容器，溢出部分裁切
        // 这是 Apple 原生相机的做法：preserves aspect ratio, crops overflow
        // 不可能拉伸变形，因为 aspectFill 按定义保持宽高比
        // 之前用 .resizeAspect 导致容器与画面比例不匹配时出现拉伸假象
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        view.onTapToFocus = onTapToFocus
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onTapToFocus = onTapToFocus
        // Defense-in-depth: 每次 SwiftUI 刷新都重新 assert videoGravity
        // 必须始终保持 resizeAspectFill（Apple 原生相机默认行为）
        if uiView.previewLayer.videoGravity != .resizeAspectFill {
            uiView.previewLayer.videoGravity = .resizeAspectFill
        }
    }
}

class CameraPreviewUIView: UIView {
    var onTapToFocus: ((CGPoint) -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    // ✅ SwiftUI 改变容器大小时（旋转/布局更新）同步 layer bounds
    // 防止 layer 残留旧尺寸导致画面被拉伸或留白
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: location)
        onTapToFocus?(devicePoint)
    }
}

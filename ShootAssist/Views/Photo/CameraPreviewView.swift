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
        // .resizeAspect = 等比显示全部内容，容器不足的部分留黑边
        // 绝不拉伸绝不裁切，是前置摄像头变形问题的唯一彻底解法
        // 付出的代价是上下/左右可能有黑边，但与系统相机照片模式 UX 一致
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        view.onTapToFocus = onTapToFocus
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
        uiView.onTapToFocus = onTapToFocus
        // Defense-in-depth: 每次 SwiftUI 刷新都重新 assert videoGravity
        // 防止任何外部代码意外改成 resizeAspectFill 导致拉伸
        if uiView.previewLayer.videoGravity != .resizeAspect {
            uiView.previewLayer.videoGravity = .resizeAspect
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

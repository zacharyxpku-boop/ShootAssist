import SwiftUI
import AVFoundation

// MARK: - UIKit 相机预览层桥接
/// AVCaptureVideoPreviewLayer 对前置摄像头已自动镜像（automaticallyAdjustsVideoMirroring = true），
/// 无需手动 transform。保存的照片由 AVCapturePhotoOutput 输出正向数据，也无需额外处理。
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}

class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

import SwiftUI
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - 视频选择器（PHPickerViewController 包装）
// 用法：.sheet(isPresented: $show) { VideoPicker { asset in ... } }

struct VideoPicker: UIViewControllerRepresentable {
    /// 选择完成回调：成功传入 AVAsset，取消或失败传 nil
    var onPick: (AVAsset?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (AVAsset?) -> Void
        init(onPick: @escaping (AVAsset?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let result = results.first else { onPick(nil); return }

            result.itemProvider.loadFileRepresentation(
                forTypeIdentifier: UTType.movie.identifier
            ) { [weak self] url, error in
                guard let self else { return }

                guard let sourceURL = url, error == nil else {
                    DispatchQueue.main.async { self.onPick(nil) }
                    return
                }

                // 复制到 app 临时目录（PHPicker 提供的 url 是沙盒临时访问权）
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("sa_import_\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)")
                do {
                    try? FileManager.default.removeItem(at: dest)  // 先清理可能残留的旧文件
                    try FileManager.default.copyItem(at: sourceURL, to: dest)
                    let asset = AVURLAsset(url: dest)
                    DispatchQueue.main.async { self.onPick(asset) }
                } catch {
                    DispatchQueue.main.async { self.onPick(nil) }
                }
            }
        }
    }
}

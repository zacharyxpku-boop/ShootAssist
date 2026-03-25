import Photos

// MARK: - 视频保存工具
class VideoSaver {
    static func save(videoURL: URL, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success)
                }
                // 清理临时文件
                if success {
                    try? FileManager.default.removeItem(at: videoURL)
                }
            }
        }
    }
}

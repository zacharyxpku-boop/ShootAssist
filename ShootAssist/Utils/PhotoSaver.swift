import Photos
import UIKit

// MARK: - 照片保存工具
class PhotoSaver {
    static func save(imageData: Data, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: imageData, options: nil)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
}

import Photos
import UIKit
import AVFoundation

/// Bridges PHAsset -> concrete media for SwiftUI views.
/// requestImage can call back more than once (degraded preview, then final);
/// the box guarantees the continuation resumes exactly once, with the
/// highest-quality image delivered.
enum AssetMediaLoader {

    private final class ResumeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<UIImage?, Never>?
        private var best: UIImage?
        private var resumed = false
        init(_ c: CheckedContinuation<UIImage?, Never>) { continuation = c }
        func offer(_ image: UIImage?, isDegraded: Bool) {
            lock.lock()
            if let image { best = image }
            let shouldResume = !isDegraded && !resumed
            let result = best
            if shouldResume { resumed = true }
            lock.unlock()
            if shouldResume { continuation?.resume(returning: result) }
        }
        func finish() {
            lock.lock()
            if resumed { lock.unlock(); return }
            resumed = true
            let result = best
            lock.unlock()
            continuation?.resume(returning: result)
        }
    }

    static func image(for asset: PHAsset,
                      targetSize: CGSize = CGSize(width: 520, height: 400)) async -> UIImage? {
        await withCheckedContinuation { cont in
            let box = ResumeBox(cont)
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(
                for: asset, targetSize: targetSize, contentMode: .aspectFill, options: options
            ) { image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                box.offer(image, isDegraded: degraded)
                // Finish on the final callback, and also on error/cancel:
                // if a degraded preview arrived and the full image then
                // fails (iCloud hiccup), nothing else will call back and
                // the caller would hang forever without this.
                let failed = info?[PHImageErrorKey] != nil || ((info?[PHImageCancelledKey] as? Bool) ?? false)
                if !degraded || failed { box.finish() }
            }
        }
    }

    /// Player item for video assets (inline VideoPlayer / muted looping).
    static func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        await withCheckedContinuation { cont in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                cont.resume(returning: item)
            }
        }
    }

    static func fetchAssets(localIdentifiers: [String]) -> [PHAsset] {
        guard !localIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var out: [PHAsset] = []
        result.enumerateObjects { a, _, _ in out.append(a) }
        return out
    }
}

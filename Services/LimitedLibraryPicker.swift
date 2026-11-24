import Photos
import UIKit

/// Presents the system limited-library picker so Steen can add photos
/// to the app's limited access without going to Settings. The picker
/// needs a UIViewController; this finds the topmost one from the key
/// window. No-op if none is found.
enum LimitedLibraryPicker {
    static func present() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
        Log.event("Photos", "limited library picker presented")
    }
}

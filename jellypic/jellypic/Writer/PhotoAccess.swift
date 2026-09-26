import Photos
import PhotosUI
import UIKit

enum PhotoAccess {

    case denied
    case limited
    case full

    // LEGACY(ios12): PHAuthorizationStatus has no .limited and no access level below iOS 14. Freed at iOS 14.
    static var current: PhotoAccess {
        if #available(iOS 14.0, *) {
            switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
            case .authorized:
                return .full
            case .limited:
                return .limited
            default:
                return .denied
            }
        }
        return PHPhotoLibrary.authorizationStatus() == .authorized ? .full : .denied
    }

    // LEGACY(ios12): requestAuthorization(for:) arrives at iOS 14 and deprecates the bare form. Freed at iOS 14.
    static func request(completion: @escaping (PhotoAccess) -> Void) {
        let deliver: () -> Void = {
            let resolved = current
            DispatchQueue.main.async { completion(resolved) }
        }
        if #available(iOS 14.0, *) {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in deliver() }
        } else {
            PHPhotoLibrary.requestAuthorization { _ in deliver() }
        }
    }

    // LEGACY(ios12): presentLimitedLibraryPicker arrives at iOS 14; below it .limited cannot occur. Freed at iOS 14.
    static func presentLimitedPicker(from viewController: UIViewController) {
        if #available(iOS 14.0, *) {
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
        }
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    var allowsLibraryRead: Bool {
        return self != .denied
    }

    var allowsAutomaticBackup: Bool {
        return self == .full
    }
}

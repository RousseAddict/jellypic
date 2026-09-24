import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    // LEGACY(ios12): pre-UIScene lifecycle. Freed at iOS 13.
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // LEGACY(ios12): setMinimumBackgroundFetchInterval, replaced by BGTaskScheduler at iOS 13.
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = RootViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    // LEGACY(ios12): performFetchWithCompletionHandler, replaced by BGTaskScheduler at iOS 13.
    func application(
        _ application: UIApplication,
        performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        AppServices.shared.upload.performBackgroundSweep { found in
            completionHandler(found ? .newData : .noData)
        }
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        AppServices.shared.upload.handleBackgroundEvents(identifier: identifier,
                                                         completionHandler: completionHandler)
    }
}

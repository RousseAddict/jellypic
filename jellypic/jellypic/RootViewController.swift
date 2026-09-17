import UIKit

final class RootViewController: UIViewController {

    private let services: AppServices
    private var current: UIViewController?

    init(services: AppServices = .shared) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.palette.background
        showCurrentDestination(animated: false)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return Theme.isDark ? .lightContent : .default
    }

    private var isSignedIn: Bool {
        return services.authStore.credentials != nil && Preferences.libraryId != nil
    }

    private func showCurrentDestination(animated: Bool) {
        if isSignedIn {
            let home = HomeViewController(services: services)
            home.onSignedOut = { [weak self] in
                self?.showCurrentDestination(animated: true)
            }
            transition(to: home, animated: animated)
        } else {
            let connect = ConnectViewController(services: services)
            connect.onFinished = { [weak self] in
                self?.showCurrentDestination(animated: true)
            }
            transition(to: connect, animated: animated)
        }
    }

    private func transition(to controller: UIViewController, animated: Bool) {
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        controller.view.alpha = animated ? 0 : 1
        view.addSubview(controller.view)
        controller.didMove(toParent: self)

        let previous = current
        current = controller

        guard animated else {
            previous?.willMove(toParent: nil)
            previous?.view.removeFromSuperview()
            previous?.removeFromParent()
            return
        }

        UIView.animate(withDuration: 0.3,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        controller.view.alpha = 1
                        previous?.view.alpha = 0
                       },
                       completion: { _ in
                        previous?.willMove(toParent: nil)
                        previous?.view.removeFromSuperview()
                        previous?.removeFromParent()
                       })
    }
}

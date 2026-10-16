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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.palette.background
        showCurrentDestination(animated: false)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(revalidateSession),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: Theme.didChangeNotification,
                                               object: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyInterfaceStyle()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // LEGACY(ios12): the OS appearance cannot change below iOS 13, so there is nothing to follow. Freed at iOS 13.
        if #available(iOS 13.0, *) {
            guard Theme.mode == .system,
                  traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
            NotificationCenter.default.post(name: Theme.didChangeNotification, object: nil)
        }
    }

    @objc private func themeDidChange() {
        view.backgroundColor = Theme.palette.background
        applyInterfaceStyle()
        setNeedsStatusBarAppearanceUpdate()
    }

    private func applyInterfaceStyle() {
        // LEGACY(ios12): overrideUserInterfaceStyle arrives at iOS 13, where system UI has a dark appearance to opt out of. Freed at iOS 13.
        if #available(iOS 13.0, *) {
            switch Theme.mode {
            case .system:
                view.window?.overrideUserInterfaceStyle = .unspecified
            case .light:
                view.window?.overrideUserInterfaceStyle = .light
            case .dark:
                view.window?.overrideUserInterfaceStyle = .dark
            }
        }
    }

    @objc private func revalidateSession() {
        guard isSignedIn else { return }
        services.revalidateSession()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        guard !Theme.isDark else { return .lightContent }
        // LEGACY(ios12): .darkContent arrives at iOS 13; below it .default is always dark text. Freed at iOS 13.
        if #available(iOS 13.0, *) {
            return .darkContent
        }
        return .default
    }

    private var isSignedIn: Bool {
        return services.hasSession && Preferences.libraryId != nil
    }

    private func showCurrentDestination(animated: Bool) {
        if isSignedIn {
            let grid = PhotoGridViewController(services: services)
            grid.onSignedOut = { [weak self] in
                self?.showCurrentDestination(animated: true)
            }
            transition(to: grid, animated: animated)
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

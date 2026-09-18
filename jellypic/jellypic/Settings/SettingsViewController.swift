import UIKit

final class SettingsViewController: UIViewController {

    private let services: AppServices

    private let dimming = UIView()
    private let card = SquircleView()
    private let titleLabel = UILabel()
    private let libraryLabel = UILabel()
    private let serverLabel = UILabel()
    private let indexLabel = UILabel()
    private let signOutButton = ActionButton()

    var onSignedOut: (() -> Void)?

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func present(over parent: UIViewController) {
        parent.addChild(self)
        view.frame = parent.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(view)
        didMove(toParent: parent)

        view.layoutIfNeeded()
        card.transform = CGAffineTransform(translationX: 0, y: card.bounds.height)
        UIView.animate(withDuration: 0.34,
                       delay: 0,
                       usingSpringWithDamping: 0.9,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.dimming.alpha = 1
                        self.card.transform = .identity
                       },
                       completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        applyPalette()
        render()
    }

    private func buildHierarchy() {
        dimming.alpha = 0
        dimming.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimming)

        card.cornerRadius = 32
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = "Settings"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        for label in [libraryLabel, serverLabel, indexLabel] {
            label.font = Typography.caption
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(label)
        }

        signOutButton.title = "Sign out"
        signOutButton.addTarget(self, action: #selector(signOut), for: .touchUpInside)
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 32),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            libraryLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            libraryLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            libraryLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            serverLabel.topAnchor.constraint(equalTo: libraryLabel.bottomAnchor, constant: 4),
            serverLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            serverLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            indexLabel.topAnchor.constraint(equalTo: serverLabel.bottomAnchor, constant: 4),
            indexLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            indexLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            signOutButton.topAnchor.constraint(equalTo: indexLabel.bottomAnchor, constant: 24),
            signOutButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            signOutButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            signOutButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissCard))
        dimming.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissCard))
        swipe.direction = .down
        card.addGestureRecognizer(swipe)
    }

    private func render() {
        libraryLabel.text = Preferences.libraryName ?? "Library"
        serverLabel.text = services.authStore.credentials?.baseURL.absoluteString
        let total = Preferences.syncTotal
        let indexed = services.store.count()
        indexLabel.text = Preferences.syncCompleted
            ? "\(indexed) photos indexed"
            : "\(indexed) of \(total) photos indexed"
    }

    @objc private func dismissCard() {
        UIView.animate(withDuration: 0.26,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.dimming.alpha = 0
                        self.card.transform = CGAffineTransform(translationX: 0,
                                                                y: self.card.bounds.height)
                       },
                       completion: { _ in
                        self.willMove(toParent: nil)
                        self.view.removeFromSuperview()
                        self.removeFromParent()
                       })
    }

    @objc private func signOut() {
        signOutButton.isLoading = true
        services.signOut { [weak self] in
            guard let self = self else { return }
            self.signOutButton.isLoading = false
            self.willMove(toParent: nil)
            self.view.removeFromSuperview()
            self.removeFromParent()
            self.onSignedOut?()
        }
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = .clear
        dimming.backgroundColor = UIColor(white: 0, alpha: 0.4)
        card.fillColor = palette.surface
        card.applyShadow(palette)
        titleLabel.textColor = palette.textPrimary
        libraryLabel.textColor = palette.textSecondary
        serverLabel.textColor = palette.textSecondary
        indexLabel.textColor = palette.textSecondary
        view.applyThemeRecursively(palette)
    }
}

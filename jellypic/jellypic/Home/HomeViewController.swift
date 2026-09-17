import UIKit

final class HomeViewController: UIViewController {

    private let services: AppServices

    private let card = SquircleView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let signOutButton = ActionButton()

    var onSignedOut: (() -> Void)?

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        card.cornerRadius = 28
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.text = Preferences.libraryName ?? "Library"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        detailLabel.font = Typography.caption
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0
        detailLabel.text = services.authStore.credentials?.baseURL.absoluteString
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(detailLabel)

        signOutButton.title = "Sign out"
        signOutButton.addTarget(self, action: #selector(signOut), for: .touchUpInside)
        signOutButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(signOutButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            signOutButton.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 24),
            signOutButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            signOutButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            signOutButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])

        applyPalette()
    }

    @objc private func signOut() {
        signOutButton.isLoading = true
        services.signOut { [weak self] in
            self?.signOutButton.isLoading = false
            self?.onSignedOut?()
        }
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = palette.background
        card.fillColor = palette.surface
        card.applyShadow(palette)
        titleLabel.textColor = palette.textPrimary
        detailLabel.textColor = palette.textSecondary
        view.applyThemeRecursively(palette)
    }
}

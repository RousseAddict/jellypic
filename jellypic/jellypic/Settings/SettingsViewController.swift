import UIKit

final class SettingsViewController: UIViewController {

    private let services: AppServices

    private let dimming = UIView()
    private let card = SquircleView()
    private let scrollView = UIScrollView()
    private let content = UIStackView()

    private let libraryLabel = UILabel()
    private let serverLabel = UILabel()
    private let indexLabel = UILabel()

    private let themeControl = UISegmentedControl()
    private let cacheRow = SettingsRowView()
    private let resyncRow = SettingsRowView()
    private let signOutRow = SettingsRowView()

    private var sectionLabels: [UILabel] = []
    private var themeModes: [ThemeMode] = []

    var onSignedOut: (() -> Void)?
    var onResyncRequested: (() -> Void)?

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

        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scrollView)

        content.axis = .vertical
        content.spacing = 18
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        buildIdentity()
        buildThemeControl()

        cacheRow.title = "Image cache"
        cacheRow.addTarget(self, action: #selector(resetCache), for: .touchUpInside)

        resyncRow.title = "Resync library"
        resyncRow.addTarget(self, action: #selector(confirmResync), for: .touchUpInside)

        signOutRow.title = "Sign out"
        signOutRow.isDestructive = true
        signOutRow.addTarget(self, action: #selector(confirmSignOut), for: .touchUpInside)

        content.addArrangedSubview(section("Appearance",
                                           SettingsGroupView(rows: [themeControl], padding: 8)))
        content.addArrangedSubview(section("Storage",
                                           SettingsGroupView(rows: [cacheRow, resyncRow], padding: 0)))
        content.addArrangedSubview(section("Account",
                                           SettingsGroupView(rows: [signOutRow], padding: 0)))

        let fit = scrollView.heightAnchor.constraint(equalTo: content.heightAnchor)
        fit.priority = UILayoutPriority(999)

        NSLayoutConstraint.activate([
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 32),
            card.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.92),

            scrollView.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            scrollView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                               constant: -24),
            fit,

            content.topAnchor.constraint(equalTo: scrollView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissCard))
        dimming.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissCard))
        swipe.direction = .down
        card.addGestureRecognizer(swipe)
    }

    private func buildIdentity() {
        libraryLabel.font = Typography.title
        libraryLabel.adjustsFontForContentSizeCategory = true
        libraryLabel.numberOfLines = 0

        for label in [serverLabel, indexLabel] {
            label.font = Typography.caption
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
        }

        let identity = UIStackView(arrangedSubviews: [libraryLabel, serverLabel, indexLabel])
        identity.axis = .vertical
        identity.spacing = 3
        identity.setCustomSpacing(8, after: libraryLabel)
        content.addArrangedSubview(identity)
        content.setCustomSpacing(22, after: identity)
    }

    private func section(_ title: String, _ group: SettingsGroupView) -> UIStackView {
        let header = UILabel()
        header.font = Typography.sectionHeader
        header.adjustsFontForContentSizeCategory = true
        header.attributedText = NSAttributedString(string: title.uppercased(),
                                                   attributes: [.kern: 0.9])
        sectionLabels.append(header)

        let stack = UIStackView(arrangedSubviews: [header, group])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func buildThemeControl() {
        var modes: [ThemeMode] = [.light, .dark]
        var titles = ["Light", "Dark"]

        // LEGACY(ios12): userInterfaceStyle does not exist, so "System" could only ever answer light. Freed at iOS 13.
        if #available(iOS 13.0, *) {
            modes.insert(.system, at: 0)
            titles.insert("System", at: 0)
        }

        themeModes = modes
        for (index, title) in titles.enumerated() {
            themeControl.insertSegment(withTitle: title, at: index, animated: false)
        }
        themeControl.selectedSegmentIndex = themeModes.firstIndex(of: Theme.mode)
            ?? themeModes.firstIndex(of: Theme.isDark ? .dark : .light)
            ?? 0
        themeControl.addTarget(self, action: #selector(themeChanged), for: .valueChanged)
    }

    private func render() {
        libraryLabel.text = Preferences.libraryName ?? "Library"
        serverLabel.text = services.authStore.credentials?.baseURL.absoluteString
        let total = Preferences.syncTotal
        let indexed = services.store.count()
        indexLabel.text = Preferences.syncCompleted
            ? "\(indexed) photos indexed"
            : "\(indexed) of \(total) photos indexed"
        cacheRow.detail = SettingsViewController.sizeText(services.images.diskUsage())
    }

    private static func sizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @objc private func themeChanged() {
        let index = themeControl.selectedSegmentIndex
        guard index >= 0, index < themeModes.count else { return }
        Theme.mode = themeModes[index]
        applyPalette()
    }

    @objc private func resetCache() {
        let reclaimed = services.images.diskUsage()
        services.images.clearCaches()
        cacheRow.detail = reclaimed > 0
            ? "Cleared \(SettingsViewController.sizeText(reclaimed))"
            : "Empty"
    }

    @objc private func confirmResync() {
        let known = max(Preferences.syncTotal, services.store.count())
        let scope = known > 0 ? "all \(known) photos" : "the whole library"
        let alert = UIAlertController(title: "Resync the library?",
                                      message: "jellypic will re-read \(scope) from the server. That takes a while on this device, and the photos you already have stay visible while it runs.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Resync", style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.onResyncRequested?()
            self.dismissCard()
        })
        present(alert, animated: true, completion: nil)
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

    @objc private func confirmSignOut() {
        let indexed = services.store.count()
        let scope = indexed > 0
            ? "The \(indexed) photos indexed on this device are deleted, along with the cached images."
            : "The index and the cached images on this device are deleted."
        let alert = UIAlertController(title: "Sign out?",
                                      message: "\(scope) Nothing on the server changes, and signing back in re-indexes the library from scratch.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Sign out", style: .destructive) { [weak self] _ in
            self?.signOut()
        })
        present(alert, animated: true, completion: nil)
    }

    private func signOut() {
        signOutRow.isEnabled = false
        signOutRow.detail = "Signing out…"
        services.signOut { [weak self] in
            guard let self = self else { return }
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
        libraryLabel.textColor = palette.textPrimary
        serverLabel.textColor = palette.textSecondary
        indexLabel.textColor = palette.textSecondary
        for label in sectionLabels {
            label.textColor = palette.textSecondary
        }
        themeControl.tintColor = palette.accent
        themeControl.backgroundColor = palette.surface
        view.applyThemeRecursively(palette)
    }
}

final class SettingsGroupView: UIView, Themed {

    private let background = SquircleView()
    private let stack = UIStackView()
    private var separators: [UIView] = []

    init(rows: [UIView], padding: CGFloat) {
        super.init(frame: .zero)
        backgroundColor = .clear

        background.cornerRadius = 16
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, row) in rows.enumerated() {
            if index > 0 {
                stack.addArrangedSubview(makeSeparator())
            }
            stack.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private func makeSeparator() -> UIView {
        let container = UIView()
        let line = UIView()
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
            line.topAnchor.constraint(equalTo: container.topAnchor),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        separators.append(line)
        return container
    }

    func applyTheme(_ palette: ThemePalette) {
        background.fillColor = palette.field
        for line in separators {
            line.backgroundColor = palette.separator
        }
    }
}

final class SettingsRowView: UIControl, Themed {

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var detail: String? {
        didSet { detailLabel.text = detail }
    }

    var isDestructive = false {
        didSet { applyTheme(Theme.palette) }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.5 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.font = Typography.body
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        detailLabel.font = Typography.caption
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textAlignment = .right
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor,
                                                 constant: 12),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    func applyTheme(_ palette: ThemePalette) {
        titleLabel.textColor = isDestructive ? palette.danger : palette.textPrimary
        detailLabel.textColor = palette.textSecondary
    }
}

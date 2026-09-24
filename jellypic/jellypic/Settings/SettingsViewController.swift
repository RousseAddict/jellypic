import UIKit

final class SettingsViewController: CardSheetViewController {

    private let services: AppServices

    private let identity = UIStackView()

    private let libraryLabel = UILabel()
    private let serverLabel = UILabel()
    private let indexLabel = UILabel()

    private let backupControl = UISegmentedControl()
    private let backupNote = SettingsNoteView()
    private let sendRow = SettingsRowView()
    private let backupModes: [BackupMode] = [.off, .manual, .automatic]

    private lazy var sendGroup = SettingsGroupView(rows: [sendRow], padding: 0)

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

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        applyPalette()
        render()
        services.upload.refreshAvailability { [weak self] in self?.renderBackup() }
    }

    private func buildHierarchy() {
        buildIdentity()
        buildBackupControl()
        buildThemeControl()

        sendRow.title = "Send my latest photo"
        sendRow.addTarget(self, action: #selector(sendLatestPhoto), for: .touchUpInside)

        cacheRow.title = "Image cache"
        cacheRow.addTarget(self, action: #selector(resetCache), for: .touchUpInside)

        resyncRow.title = "Resync library"
        resyncRow.addTarget(self, action: #selector(confirmResync), for: .touchUpInside)

        signOutRow.title = "Sign out"
        signOutRow.isDestructive = true
        signOutRow.addTarget(self, action: #selector(confirmSignOut), for: .touchUpInside)

        body.addArrangedSubview(section("Backup",
                                        [SettingsGroupView(rows: [backupControl, backupNote], padding: 8),
                                         sendGroup]))
        body.addArrangedSubview(section("Appearance",
                                        [SettingsGroupView(rows: [themeControl], padding: 8)]))
        body.addArrangedSubview(section("Storage",
                                        [SettingsGroupView(rows: [cacheRow, resyncRow], padding: 0)]))
        body.addArrangedSubview(section("Account",
                                        [SettingsGroupView(rows: [signOutRow], padding: 0)]))
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

        for label in [libraryLabel, serverLabel, indexLabel] {
            identity.addArrangedSubview(label)
        }
        identity.axis = .vertical
        identity.spacing = 3
        identity.setCustomSpacing(8, after: libraryLabel)
        setHeaderView(identity)
    }

    private func section(_ title: String, _ groups: [SettingsGroupView]) -> UIStackView {
        let header = UILabel()
        header.font = Typography.sectionHeader
        header.adjustsFontForContentSizeCategory = true
        header.attributedText = NSAttributedString(string: title.uppercased(),
                                                   attributes: [.kern: 0.9])
        sectionLabels.append(header)

        let stack = UIStackView(arrangedSubviews: [header] + groups)
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func buildBackupControl() {
        for (index, title) in ["Off", "Manual", "Automatic"].enumerated() {
            backupControl.insertSegment(withTitle: title, at: index, animated: false)
        }
        backupControl.selectedSegmentIndex = backupModes.firstIndex(of: services.upload.mode) ?? 0
        backupControl.addTarget(self, action: #selector(backupModeChanged), for: .valueChanged)
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
        renderBackup()
    }

    private func renderBackup() {
        backupControl.isEnabled = services.upload.availability.allowsChanges
        backupNote.text = backupNoteText()
        sendGroup.isHidden = services.upload.mode == .off
        if case .ready = services.upload.availability {
            sendRow.isEnabled = true
        } else {
            sendRow.isEnabled = false
        }
    }

    private func backupNoteText() -> String {
        switch services.upload.availability {
        case .notInstalled:
            return "Requires the upload plugin on your server"
        case .incompatible:
            return "Update the upload plugin on your server"
        case .blocked(let reason):
            return reason
        case .unknown, .ready:
            switch services.upload.mode {
            case .off:
                return "Photos taken on this device stay on this device"
            case .manual:
                return "Choose photos on the grid to send them"
            case .automatic:
                return "New photos are sent in the background\n" + sweepNoteText()
            }
        }
    }

    private func sweepNoteText() -> String {
        guard let at = services.upload.lastSweepAt else {
            return "Waiting for the first background check"
        }
        let result = services.upload.lastSweepResult ?? "checked"
        return "Last checked \(SettingsViewController.sweepFormatter.string(from: at)) — \(result)"
    }

    private static let sweepFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    private static func sizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    @objc private func backupModeChanged() {
        let index = backupControl.selectedSegmentIndex
        guard index >= 0, index < backupModes.count else { return }
        services.upload.mode = backupModes[index]
        renderBackup()
    }

    @objc private func sendLatestPhoto() {
        sendRow.isEnabled = false
        sendRow.detail = "Sending…"

        services.upload.uploadMostRecentPhoto { [weak self] result in
            guard let self = self else { return }
            self.sendRow.detail = nil
            self.renderBackup()

            switch result {
            case .success(let receipt):
                self.report(title: receipt.created ? "Sent" : "Already there",
                            message: receipt.created
                                ? "Filed as \(receipt.path).\n\nYour server picks up new photos after about a minute; Jellypic will show it the next time you open the grid."
                                : "Your server already had this photo, as \(receipt.path).")
            case .failure(let failure):
                self.report(title: "Not sent", message: failure.text)
            }
        }
    }

    private func report(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
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
            self.onDismissed = self.onSignedOut
            self.dismissCard()
        }
    }

    private func applyPalette() {
        let palette = Theme.palette
        applySheetPalette(palette)
        libraryLabel.textColor = palette.textPrimary
        serverLabel.textColor = palette.textSecondary
        indexLabel.textColor = palette.textSecondary
        for label in sectionLabels {
            label.textColor = palette.textSecondary
        }
        for control in [backupControl, themeControl] {
            control.tintColor = palette.accent
            control.backgroundColor = palette.surface
        }
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

final class SettingsNoteView: UIView, Themed {

    private let label = UILabel()

    var text: String? {
        didSet { label.text = text }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        label.font = Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func applyTheme(_ palette: ThemePalette) {
        label.textColor = palette.textSecondary
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

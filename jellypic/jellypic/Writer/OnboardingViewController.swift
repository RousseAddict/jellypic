import UIKit

final class OnboardingViewController: CardSheetViewController {

    private enum Page {
        case server
        case howTo
        case backup
    }

    private let services: AppServices
    private let hasServerStep: Bool
    private var page: Page
    private var selection: BackupMode
    private var accessNote: String?
    private var hasAskedForAccess = false
    private var isChecking = false
    private var measuredWidth: CGFloat = 0
    private var fixedHeight: CGFloat = 0
    private var needsMeasure = true

    private let topBar = UIView()
    private let backButton = GlyphButton(glyph: BackGlyphView())
    private let stepIndicator = StepIndicatorView(count: 2)
    private let mainButton = ActionButton()

    private let serverPage = UIStackView()
    private let serverTitle = UILabel()
    private let serverSubtitle = UILabel()
    private let checkedLabel = UILabel()
    private let checkAgain = TextLinkControl(title: "Check again")
    private let uploadLine = StatusLineView()
    private let heicLine = StatusLineView()
    private let helpRow = LinkRowView(height: 52)

    private let howToPage = UIStackView()
    private let howToTitle = UILabel()
    private let stepsStack = UIStackView()

    private let backupPage = UIStackView()
    private let backupTitle = UILabel()
    private let offRow = ModeRowView(title: "Off", detail: "Browse only — nothing is sent")
    private let manualRow = ModeRowView(title: "Manual", detail: "You choose photos with +")
    private let automaticRow: ModeRowView
    private let olderSwitch = UISwitch()
    private let olderTitle = UILabel()
    private let olderDetail = UILabel()
    private let accessRow = LinkRowView(height: 48)
    private let footnote = UILabel()

    init(services: AppServices, startsAtServer: Bool) {
        self.services = services
        self.selection = services.upload.mode

        let olderRow = UIView()
        self.automaticRow = ModeRowView(title: "Automatic", detail: "New photos · Wi-Fi only", extensionView: olderRow)

        let setup = OnboardingViewController.setup(for: services)
        self.hasServerStep = startsAtServer || setup.needsAttention
        self.page = hasServerStep ? .server : .backup

        super.init(nibName: nil, bundle: nil)
        buildOlderRow(in: olderRow)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func prepare(_ services: AppServices, completion: @escaping () -> Void) {
        let group = DispatchGroup()
        group.enter()
        services.upload.refreshAvailability { group.leave() }
        group.enter()
        services.upload.refreshHeicStatus { group.leave() }
        group.notify(queue: .main, execute: completion)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sheetTopPadding = 8
        sheetSpacing = 8
        body.spacing = 0
        buildTopBar()
        buildServerPage()
        buildHowToPage()
        buildBackupPage()

        mainButton.addTarget(self, action: #selector(mainTapped), for: .touchUpInside)
        footer.addArrangedSubview(mainButton)
        footer.isHidden = false

        renderServer()
        renderBackup()
        show(page, animated: false)
        applyPalette()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }

    override func present(over parent: UIViewController) {
        loadViewIfNeeded()
        view.frame = parent.view.bounds
        view.layoutIfNeeded()
        super.present(over: parent)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let width = body.bounds.width
        guard width > 0, width != measuredWidth || needsMeasure else { return }
        measuredWidth = width
        needsMeasure = false

        let tallest = pagesInFlow().map { measuredHeight(of: $0, width: width) }.max() ?? 0
        guard tallest > fixedHeight else { return }
        fixedHeight = tallest
        setFixedBodyHeight(tallest)
    }

    private static func setup(for services: AppServices) -> ServerSetup {
        return ServerSetup(availability: services.upload.availability,
                           heic: services.upload.heicStatus,
                           isAdministrator: Preferences.isAdministrator ?? false,
                           libraryName: Preferences.libraryName ?? "Photos",
                           serverURL: services.authStore.session?.baseURL)
    }

    private func pagesInFlow() -> [UIView] {
        var pages: [UIView] = [backupPage]
        if hasServerStep {
            pages.append(serverPage)
            if OnboardingViewController.setup(for: services).help != .share {
                pages.append(howToPage)
            }
        }
        return pages
    }

    private func measuredHeight(of page: UIView, width: CGFloat) -> CGFloat {
        let tallestBackup = page === backupPage
        let savedExpansion = automaticRow.isExpanded
        let savedFootnote = footnote.text
        if tallestBackup {
            automaticRow.isExpanded = true
            footnote.text = backupConcepts()
        }
        let height = page.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel).height
        if tallestBackup {
            automaticRow.isExpanded = savedExpansion
            footnote.text = savedFootnote
        }
        return ceil(height)
    }

    private func buildTopBar() {
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(backButton)

        stepIndicator.onSelect = { [weak self] index in self?.stepSelected(index) }
        stepIndicator.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(stepIndicator)
        setHeaderView(topBar)

        NSLayoutConstraint.activate([
            topBar.heightAnchor.constraint(equalToConstant: GlyphButton.side),
            backButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            stepIndicator.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            stepIndicator.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            stepIndicator.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func buildServerPage() {
        configureTitle(serverTitle, text: "Your server")
        configureBody(serverSubtitle)

        checkedLabel.font = Typography.sectionHeader
        checkedLabel.adjustsFontForContentSizeCategory = true
        checkAgain.addTarget(self, action: #selector(checkAgainTapped), for: .touchUpInside)

        let headerLine = UIStackView(arrangedSubviews: [checkedLabel, UIView(), checkAgain])
        headerLine.axis = .horizontal
        headerLine.alignment = .center
        headerLine.isLayoutMarginsRelativeArrangement = true
        headerLine.layoutMargins = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)

        let lines = SettingsGroupView(rows: [uploadLine, heicLine], padding: 0)
        let list = UIStackView(arrangedSubviews: [headerLine, lines])
        list.axis = .vertical
        list.spacing = 8

        helpRow.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)

        let heading = UIStackView(arrangedSubviews: [serverTitle, serverSubtitle])
        heading.axis = .vertical
        heading.spacing = 6

        configurePage(serverPage, [heading, list, helpRow], spacing: 12)
    }

    private func buildHowToPage() {
        configureTitle(howToTitle, text: "How to install")
        stepsStack.axis = .vertical
        stepsStack.spacing = 8
        configurePage(howToPage, [howToTitle, stepsStack], spacing: 10)
    }

    private func buildBackupPage() {
        configureTitle(backupTitle, text: "Backup")

        for (row, mode) in [(offRow, BackupMode.off), (manualRow, .manual), (automaticRow, .automatic)] {
            row.tag = mode.rawValue
            row.addTarget(self, action: #selector(modeTapped(_:)))
        }
        let rows = UIStackView(arrangedSubviews: [offRow, manualRow, automaticRow])
        rows.axis = .vertical
        rows.spacing = 6

        accessRow.title = "Allow access to all photos"
        accessRow.trailing = .chevron
        accessRow.addTarget(self, action: #selector(openPhotoSettings), for: .touchUpInside)

        configureCaption(footnote)
        configurePage(backupPage, [backupTitle, rows, accessRow, footnote], spacing: 10)
    }

    private func buildOlderRow(in container: UIView) {
        olderTitle.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15))
        olderTitle.adjustsFontForContentSizeCategory = true
        olderTitle.text = "Also send older photos"
        configureCaption(olderDetail)
        olderSwitch.isOn = true

        let labels = UIStackView(arrangedSubviews: [olderTitle, olderDetail])
        labels.axis = .vertical
        labels.spacing = 2

        let row = UIStackView(arrangedSubviews: [labels, olderSwitch])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])
    }

    private func configurePage(_ page: UIStackView, _ views: [UIView], spacing: CGFloat) {
        page.axis = .vertical
        page.spacing = spacing
        for view in views {
            page.addArrangedSubview(view)
        }
    }

    private func configureTitle(_ label: UILabel, text: String) {
        label.font = Typography.title
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.text = text
    }

    private func configureBody(_ label: UILabel) {
        label.font = Typography.body
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
    }

    private func configureCaption(_ label: UILabel) {
        label.font = Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
    }

    private func show(_ page: Page, animated: Bool) {
        self.page = page
        let target: UIView
        switch page {
        case .server:
            target = serverPage
        case .howTo:
            target = howToPage
        case .backup:
            target = backupPage
        }

        let swap = {
            for view in self.body.arrangedSubviews {
                self.body.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            self.body.addArrangedSubview(target)
        }

        if animated {
            UIView.transition(with: body, duration: 0.2, options: [.transitionCrossDissolve], animations: swap)
        } else {
            swap()
        }
        scrollBodyToTop()
        updateChrome()
    }

    private func updateChrome() {
        let canGoBack = page == .howTo || (page == .backup && hasServerStep)
        backButton.alpha = canGoBack ? 1 : 0
        backButton.isUserInteractionEnabled = canGoBack

        stepIndicator.isHidden = !hasServerStep
        stepIndicator.update(current: page == .backup ? 1 : 0, reachable: 1, animated: false)

        mainButton.title = page == .backup ? "Done" : "Next"
    }

    private func renderServer() {
        let setup = OnboardingViewController.setup(for: services)
        serverSubtitle.text = setup.subtitle
        checkedLabel.attributedText = NSAttributedString(string: isChecking ? "CHECKING…" : "CHECKED JUST NOW",
                                                         attributes: [.kern: 0.9,
                                                                      .font: Typography.sectionHeader,
                                                                      .foregroundColor: Theme.palette.textSecondary])
        checkAgain.isEnabled = !isChecking
        uploadLine.configure(setup.uploadLine)
        heicLine.configure(setup.heicLine)

        helpRow.title = setup.help.title
        helpRow.trailing = setup.help == .share ? .share : .chevron

        howToTitle.text = setup.help == .finish ? "How to finish setup" : "How to install"
        renderSteps(setup)

        needsMeasure = true
        view.setNeedsLayout()
    }

    private func renderSteps(_ setup: ServerSetup) {
        for view in stepsStack.arrangedSubviews {
            stepsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for (index, text) in setup.steps.enumerated() {
            stepsStack.addArrangedSubview(StepTextView(number: index + 1, text: text))
            if index == 0, !setup.links.isEmpty {
                let rows = setup.links.map { link -> LinkRowView in
                    let row = LinkRowView(height: 44)
                    row.title = "\(link.name) link"
                    row.trailing = .text("Copy")
                    row.onTap = { [weak row] in
                        UIPasteboard.general.string = link.url.absoluteString
                        row?.flash("Copied")
                    }
                    return row
                }
                stepsStack.addArrangedSubview(SettingsGroupView(rows: rows, padding: 0))
            }
        }

        if let url = setup.dashboardURL {
            let open = LinkRowView(height: 48)
            open.title = "Open plugin settings"
            open.trailing = .external
            open.onTap = { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            if let last = stepsStack.arrangedSubviews.last {
                stepsStack.setCustomSpacing(12, after: last)
            }
            stepsStack.addArrangedSubview(open)
        }
        stepsStack.applyThemeRecursively(Theme.palette)
    }

    private func renderBackup() {
        let allowsChanges = services.upload.availability.allowsChanges
        manualRow.isEnabled = allowsChanges
        automaticRow.isEnabled = allowsChanges

        offRow.isOn = selection == .off
        manualRow.isOn = selection == .manual
        automaticRow.isOn = selection == .automatic
        automaticRow.isExpanded = selection == .automatic

        if let count = services.upload.localPhotoCount() {
            olderDetail.text = count == 1 ? "1 already on this iPhone" : "\(count) already on this iPhone"
        } else {
            olderDetail.text = "Photos already on this iPhone"
        }

        accessRow.isHidden = accessNote == nil
        footnote.text = footnoteText(allowsChanges: allowsChanges)
    }

    private func footnoteText(allowsChanges: Bool) -> String {
        if let note = accessNote {
            return note
        }
        guard allowsChanges else {
            return "Manual and Automatic need Upload for Jelly on your server. Turn backup on in Settings once it is ready."
        }
        switch selection {
        case .off:
            return "Nothing leaves this iPhone. You can turn backup on later in Settings."
        case .manual:
            return backupConcepts()
        case .automatic:
            guard UIApplication.shared.backgroundRefreshStatus == .available else {
                return backupConcepts()
                    + "\nBackground App Refresh is off for Jellypic: new photos go only while the app is open."
            }
            return backupConcepts()
        }
    }

    private func backupConcepts() -> String {
        let library = Preferences.libraryName ?? "Photos"
        return "Photos only, not videos. Deleting here keeps the server copy. "
            + "Anyone who can open “\(library)” on your server sees them."
    }

    private func select(_ mode: BackupMode) {
        accessNote = nil
        guard mode == .automatic else {
            selection = mode
            renderBackup()
            return
        }

        switch PhotoAccess.current {
        case .full:
            selection = .automatic
        case .limited:
            accessNote = "Automatic backup needs access to all photos: a photo taken later never joins a limited selection."
        case .denied:
            guard !PhotoAccess.wasRefused, !hasAskedForAccess else {
                accessNote = "Jellypic cannot see your photos. Allow access to send them automatically."
                break
            }
            hasAskedForAccess = true
            PhotoAccess.request { [weak self] _ in self?.select(.automatic) }
            return
        }
        renderBackup()
    }

    private func finish() {
        let upload = services.upload
        switch selection {
        case .off:
            if upload.mode != .off {
                upload.mode = .off
            }
        case .manual:
            upload.mode = .manual
        case .automatic:
            if upload.mode != .automatic {
                upload.mode = .automatic
            }
            if upload.catchUp.phase == .offered {
                if olderSwitch.isOn {
                    upload.beginCatchUp()
                } else {
                    upload.declineCatchUp()
                }
            }
        }
        dismissCard()
    }

    private func recheck() {
        guard !isChecking else { return }
        isChecking = true
        renderServer()
        OnboardingViewController.prepare(services) { [weak self] in
            guard let self = self else { return }
            self.isChecking = false
            self.renderServer()
            self.renderBackup()
        }
    }

    private func stepSelected(_ index: Int) {
        guard hasServerStep else { return }
        show(index == 0 ? .server : .backup, animated: true)
    }

    @objc private func mainTapped() {
        switch page {
        case .server, .howTo:
            show(.backup, animated: true)
        case .backup:
            finish()
        }
    }

    @objc private func backTapped() {
        show(.server, animated: true)
    }

    @objc private func helpTapped() {
        let setup = OnboardingViewController.setup(for: services)
        guard setup.help == .share else {
            show(.howTo, animated: true)
            return
        }
        let share = UIActivityViewController(activityItems: [setup.shareText], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = helpRow
        share.popoverPresentationController?.sourceRect = helpRow.bounds
        present(share, animated: true, completion: nil)
    }

    @objc private func checkAgainTapped() {
        recheck()
    }

    @objc private func modeTapped(_ sender: UIControl) {
        guard let mode = BackupMode(rawValue: sender.tag) else { return }
        select(mode)
    }

    @objc private func openPhotoSettings() {
        PhotoAccess.openSystemSettings()
    }

    @objc private func applicationDidBecomeActive() {
        if page == .backup {
            if accessNote != nil, PhotoAccess.current == .full {
                select(.automatic)
            } else {
                renderBackup()
            }
        } else {
            recheck()
        }
    }

    private func applyPalette() {
        let palette = Theme.palette
        applySheetPalette(palette)
        for label in [serverTitle, howToTitle, backupTitle, olderTitle] {
            label.textColor = palette.textPrimary
        }
        for label in [serverSubtitle, checkedLabel, olderDetail, footnote] {
            label.textColor = palette.textSecondary
        }
        olderSwitch.onTintColor = palette.accent
        view.applyThemeRecursively(palette)
        for page in [serverPage, howToPage, backupPage] where page.superview == nil {
            page.applyThemeRecursively(palette)
        }
    }
}

private final class StatusLineView: UIView, Themed {

    private let badge = CircleView()
    private let cross = CloseGlyphView(size: CGSize(width: 10, height: 10))
    private let exclamation = ExclamationGlyphView()
    private let check = CheckmarkView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var kind: ServerSetupBadge = .attention
    private var palette = Theme.palette

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)
        for glyph in [cross, exclamation, check] as [UIView] {
            glyph.translatesAutoresizingMaskIntoConstraints = false
            badge.addSubview(glyph)
            NSLayoutConstraint.activate([
                glyph.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
                glyph.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
            ])
        }
        check.lineWidth = 1.8

        titleLabel.font = Typography.body
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        detailLabel.font = Typography.caption
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0

        let labels = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        labels.axis = .vertical
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false
        addSubview(labels)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 28),
            badge.heightAnchor.constraint(equalToConstant: 28),
            cross.widthAnchor.constraint(equalToConstant: 10),
            cross.heightAnchor.constraint(equalToConstant: 10),
            exclamation.widthAnchor.constraint(equalToConstant: 2),
            exclamation.heightAnchor.constraint(equalToConstant: 12),
            check.widthAnchor.constraint(equalToConstant: 18),
            check.heightAnchor.constraint(equalToConstant: 18),

            labels.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            labels.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            labels.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        isAccessibilityElement = true
        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(_ line: ServerSetupLine) {
        titleLabel.text = line.title
        detailLabel.text = line.detail
        accessibilityLabel = "\(line.title), \(line.detail)"
        kind = line.badge
        applyTheme(palette)
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        titleLabel.textColor = palette.textPrimary
        detailLabel.textColor = palette.textSecondary

        cross.isHidden = kind != .missing
        exclamation.isHidden = kind != .attention
        check.isHidden = kind != .ready

        cross.color = palette.danger
        exclamation.color = palette.textPrimary
        check.color = palette.onAccent

        switch kind {
        case .missing:
            badge.fillColor = palette.danger.withAlphaComponent(0.16)
        case .attention:
            badge.fillColor = palette.discFill
        case .ready:
            badge.fillColor = palette.accent
        }
    }
}

private final class LinkRowView: UIControl, Themed {

    enum Trailing {
        case chevron
        case share
        case external
        case text(String)
    }

    private let background = SquircleView()
    private let titleLabel = UILabel()
    private let trailingLabel = UILabel()
    private let trailingGlyphs: [GlyphView]
    private let height: CGFloat
    private var palette = Theme.palette
    private var flashToken = 0

    var onTap: (() -> Void)?

    var title: String = "" {
        didSet {
            titleLabel.text = title
            accessibilityLabel = title
        }
    }

    var trailing: Trailing = .chevron {
        didSet { applyTrailing() }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    init(height: CGFloat) {
        self.height = height
        self.trailingGlyphs = [ChevronGlyphView(), ShareGlyphView(), ExternalLinkGlyphView()]
        super.init(frame: .zero)
        backgroundColor = .clear

        background.cornerRadius = 14
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        titleLabel.font = Typography.body
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        trailingLabel.font = UIFontMetrics(forTextStyle: .subheadline)
            .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
        trailingLabel.adjustsFontForContentSizeCategory = true
        trailingLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(trailingLabel)

        var constraints = [
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingLabel.leadingAnchor, constant: -12),

            trailingLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            trailingLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        for glyph in trailingGlyphs {
            glyph.isUserInteractionEnabled = false
            glyph.translatesAutoresizingMaskIntoConstraints = false
            addSubview(glyph)
            constraints += [
                glyph.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
                glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
                glyph.widthAnchor.constraint(equalToConstant: glyph.glyphSize.width),
                glyph.heightAnchor.constraint(equalToConstant: glyph.glyphSize.height)
            ]
        }
        NSLayoutConstraint.activate(constraints)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = true
        accessibilityTraits = .button
        applyTrailing()
        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: height)
    }

    func flash(_ text: String) {
        guard case .text(let original) = trailing else { return }
        flashToken += 1
        let token = flashToken
        trailingLabel.text = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, self.flashToken == token else { return }
            self.trailingLabel.text = original
        }
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        background.fillColor = palette.field
        titleLabel.textColor = palette.textPrimary
        trailingLabel.textColor = palette.textPrimary
        trailingGlyphs[0].color = palette.textSecondary
        trailingGlyphs[1].color = palette.textPrimary
        trailingGlyphs[2].color = palette.textPrimary
    }

    @objc private func tapped() {
        onTap?()
    }

    private func applyTrailing() {
        let shown: Int?
        switch trailing {
        case .chevron:
            shown = 0
        case .share:
            shown = 1
        case .external:
            shown = 2
        case .text:
            shown = nil
        }
        for (index, glyph) in trailingGlyphs.enumerated() {
            glyph.isHidden = index != shown
        }
        if case .text(let text) = trailing {
            trailingLabel.text = text
            trailingLabel.isHidden = false
        } else {
            trailingLabel.text = nil
            trailingLabel.isHidden = true
        }
    }
}

private final class ModeRowView: UIView, Themed {

    private let background = SquircleView()
    private let header = ModeHeaderControl()
    private let separatorLine = UIView()
    private let separator = UIView()
    private let extensionView: UIView?
    private var palette = Theme.palette

    var isOn: Bool = false {
        didSet {
            header.indicator.isOn = isOn
            header.isSelected = isOn
        }
    }

    var isExpanded: Bool = false {
        didSet {
            separatorLine.isHidden = !isExpanded
            extensionView?.isHidden = !isExpanded
        }
    }

    var isEnabled: Bool = true {
        didSet {
            header.isEnabled = isEnabled
            alpha = isEnabled ? 1 : 0.45
        }
    }

    init(title: String, detail: String, extensionView: UIView? = nil) {
        self.extensionView = extensionView
        super.init(frame: .zero)
        backgroundColor = .clear

        background.cornerRadius = 14
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        header.titleLabel.text = title
        header.detailLabel.text = detail
        header.accessibilityLabel = "\(title), \(detail)"

        var arranged: [UIView] = [header]
        if let extensionView = extensionView {
            separator.translatesAutoresizingMaskIntoConstraints = false
            separatorLine.addSubview(separator)
            NSLayoutConstraint.activate([
                separatorLine.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
                separator.topAnchor.constraint(equalTo: separatorLine.topAnchor),
                separator.bottomAnchor.constraint(equalTo: separatorLine.bottomAnchor),
                separator.leadingAnchor.constraint(equalTo: separatorLine.leadingAnchor, constant: 16),
                separator.trailingAnchor.constraint(equalTo: separatorLine.trailingAnchor, constant: -16)
            ])
            arranged += [separatorLine, extensionView]
            separatorLine.isHidden = true
            extensionView.isHidden = true
        }

        let stack = UIStackView(arrangedSubviews: arranged)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func addTarget(_ target: Any?, action: Selector) {
        header.addTarget(target, action: action, for: .touchUpInside)
    }

    override var tag: Int {
        didSet { header.tag = tag }
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        background.fillColor = palette.field
        separator.backgroundColor = palette.separator
        header.applyTheme(palette)
    }
}

private final class ModeHeaderControl: UIControl, Themed {

    let titleLabel = UILabel()
    let detailLabel = UILabel()
    let indicator = SelectionIndicatorView()

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    override var isSelected: Bool {
        didSet { accessibilityTraits = isSelected ? [.button, .selected] : .button }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.font = Typography.body
        titleLabel.adjustsFontForContentSizeCategory = true
        detailLabel.font = Typography.caption
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.numberOfLines = 0

        for view in [titleLabel, detailLabel, indicator] as [UIView] {
            view.isUserInteractionEnabled = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 56),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: indicator.leadingAnchor, constant: -12),

            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: indicator.leadingAnchor, constant: -12),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),

            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 24),
            indicator.heightAnchor.constraint(equalToConstant: 24)
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func applyTheme(_ palette: ThemePalette) {
        titleLabel.textColor = palette.textPrimary
        detailLabel.textColor = palette.textSecondary
        indicator.applyTheme(palette)
    }
}

private final class StepTextView: UIView, Themed {

    private let badge = CircleView()
    private let numberLabel = UILabel()
    private let textLabel = UILabel()

    init(number: Int, text: String) {
        super.init(frame: .zero)
        backgroundColor = .clear

        numberLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 12, weight: .semibold))
        numberLabel.textAlignment = .center
        numberLabel.text = "\(number)"

        textLabel.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: .systemFont(ofSize: 15))
        textLabel.adjustsFontForContentSizeCategory = true
        textLabel.numberOfLines = 0
        textLabel.text = text

        for view in [badge, numberLabel, textLabel] as [UIView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: leadingAnchor),
            badge.topAnchor.constraint(equalTo: topAnchor),
            badge.widthAnchor.constraint(equalToConstant: 20),
            badge.heightAnchor.constraint(equalToConstant: 20),
            numberLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            numberLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor),

            textLabel.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: topAnchor),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        isAccessibilityElement = true
        accessibilityLabel = "Step \(number). \(text)"
        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func applyTheme(_ palette: ThemePalette) {
        badge.fillColor = palette.accent
        numberLabel.textColor = palette.onAccent
        textLabel.textColor = palette.textPrimary
    }
}

private final class TextLinkControl: UIControl, Themed {

    private let label = UILabel()

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    init(title: String) {
        super.init(frame: .zero)
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        label.text = title
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.insetBy(dx: -8, dy: -6).contains(point)
    }

    func applyTheme(_ palette: ThemePalette) {
        label.textColor = palette.textPrimary
    }
}

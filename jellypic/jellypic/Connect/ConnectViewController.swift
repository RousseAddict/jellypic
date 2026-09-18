import UIKit
import Security

final class ConnectViewController: UIViewController {

    private enum Step: Int {
        case server
        case credentials
        case library

        static let count = 3
    }

    private static let indicatorSpace: CGFloat = 62

    private let services: AppServices

    private let card = SquircleView()
    private let stepIndicator = StepIndicatorView(count: Step.count)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stepContainer = UIView()
    private let errorLabel = UILabel()
    private let actionButton = ActionButton()

    private let serverStep = ServerStepView()
    private let credentialsStep = CredentialsStepView()
    private let libraryStep = LibraryStepView()

    private var cardCenterY: NSLayoutConstraint!
    private var errorTop: NSLayoutConstraint!
    private var stepBottom: NSLayoutConstraint?

    private var step: Step = .server
    private var reachedStep: Step = .server
    private var baseURL: URL?
    private var serverName: String?
    private var keyboardHeight: CGFloat = 0

    var onFinished: (() -> Void)?

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

        serverStep.onSubmit = { [weak self] in self?.primaryAction() }
        credentialsStep.onSubmit = { [weak self] in self?.primaryAction() }
        libraryStep.onSelectionChange = { [weak self] in self?.refreshActionState() }

        stepIndicator.onSelect = { [weak self] index in self?.jump(to: index) }
        actionButton.addTarget(self, action: #selector(primaryAction), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        for direction in [UISwipeGestureRecognizer.Direction.right, .left] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: Theme.didChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)

        applyPalette()
        install(serverStep)
        serverStep.alpha = 1
        renderStep(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCardOffset()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        serverStep.focus()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func buildHierarchy() {
        card.cornerRadius = 28
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        stepIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stepIndicator)

        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        subtitleLabel.font = Typography.caption
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(subtitleLabel)

        stepContainer.backgroundColor = .clear
        stepContainer.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stepContainer)

        errorLabel.font = Typography.caption
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(errorLabel)

        actionButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(actionButton)

        cardCenterY = card.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        errorTop = errorLabel.topAnchor.constraint(equalTo: stepContainer.bottomAnchor)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cardCenterY,

            stepIndicator.topAnchor.constraint(equalTo: card.bottomAnchor, constant: 18),
            stepIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stepIndicator.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor),
            stepIndicator.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            stepContainer.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 20),
            stepContainer.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stepContainer.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            errorTop,
            errorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            errorLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            actionButton.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 18),
            actionButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -24)
        ])
    }

    private func install(_ stepView: UIView) {
        stepView.alpha = 0
        stepView.translatesAutoresizingMaskIntoConstraints = false
        stepContainer.addSubview(stepView)

        let bottom = stepView.bottomAnchor.constraint(equalTo: stepContainer.bottomAnchor)
        NSLayoutConstraint.activate([
            stepView.topAnchor.constraint(equalTo: stepContainer.topAnchor),
            stepView.leadingAnchor.constraint(equalTo: stepContainer.leadingAnchor),
            stepView.trailingAnchor.constraint(equalTo: stepContainer.trailingAnchor),
            bottom
        ])
        stepBottom = bottom
    }

    private func move(to step: Step) {
        guard step != self.step else { return }

        let outgoing = currentStepView()
        self.step = step
        let incoming = currentStepView()

        stepBottom?.isActive = false
        install(incoming)
        setError(nil)

        UIView.animate(withDuration: 0.34,
                       delay: 0,
                       usingSpringWithDamping: 0.9,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        outgoing.alpha = 0
                        incoming.alpha = 1
                        self.renderStep(animated: true)
                        self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                        outgoing.removeFromSuperview()
                        self.focusCurrentStep()
                       })
    }

    private func currentStepView() -> UIView {
        switch step {
        case .server: return serverStep
        case .credentials: return credentialsStep
        case .library: return libraryStep
        }
    }

    private func focusCurrentStep() {
        switch step {
        case .server:
            serverStep.focus()
        case .credentials:
            credentialsStep.focus()
        case .library:
            view.endEditing(true)
        }
    }

    private func renderStep(animated: Bool) {
        let title: String
        let subtitle: String
        let action: String

        switch step {
        case .server:
            title = "Your server"
            subtitle = "The address of the Jellyfin server holding your photos."
            action = "Continue"
        case .credentials:
            title = "Sign in"
            subtitle = serverName.map { "Connected to \($0)." } ?? "Your Jellyfin account."
            action = "Sign in"
        case .library:
            title = "Your photos"
            subtitle = "Pick the library jellypic should show."
            action = "Use this library"
        }

        if animated {
            crossfade(titleLabel) { self.titleLabel.text = title }
            crossfade(subtitleLabel) { self.applySubtitle(subtitle) }
            crossfade(actionButton) { self.actionButton.title = action }
        } else {
            titleLabel.text = title
            applySubtitle(subtitle)
            actionButton.title = action
        }

        stepIndicator.update(current: step.rawValue,
                             reachable: reachedStep.rawValue,
                             animated: animated)
        refreshActionState()
    }

    private func applySubtitle(_ text: String) {
        let palette = Theme.palette
        guard step == .credentials,
              let url = baseURL,
              ServerURL.isPlaintextToPublicHost(url) else {
            subtitleLabel.textColor = palette.textSecondary
            subtitleLabel.text = text
            return
        }

        let warning = "This server is not on your local network and the connection is plain HTTP. Your password will travel unencrypted."
        let subtitle = NSMutableAttributedString(string: text + "\n",
                                                 attributes: [.foregroundColor: palette.textSecondary])
        subtitle.append(NSAttributedString(string: warning,
                                           attributes: [.foregroundColor: palette.danger]))
        subtitleLabel.attributedText = subtitle
    }

    private func crossfade(_ target: UIView, changes: @escaping () -> Void) {
        UIView.transition(with: target,
                          duration: 0.2,
                          options: [.transitionCrossDissolve],
                          animations: changes,
                          completion: nil)
    }

    private func refreshActionState() {
        guard !actionButton.isLoading else { return }
        actionButton.isEnabled = step != .library || libraryStep.selected != nil
    }

    private func setError(_ message: String?) {
        errorLabel.text = message
        errorTop.constant = message == nil ? 0 : 12
    }

    private func showError(_ message: String) {
        UIView.animate(withDuration: 0.24,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.setError(message)
                        self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }

    private func setLoading(_ loading: Bool) {
        actionButton.isLoading = loading
        stepIndicator.isUserInteractionEnabled = !loading
        if !loading {
            refreshActionState()
        }
    }

    private func jump(to index: Int) {
        guard !actionButton.isLoading,
              index <= reachedStep.rawValue,
              let target = Step(rawValue: index) else { return }
        move(to: target)
    }

    @objc private func handleSwipe(_ recognizer: UISwipeGestureRecognizer) {
        let offset = recognizer.direction == .right ? -1 : 1
        jump(to: step.rawValue + offset)
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    @objc private func primaryAction() {
        guard !actionButton.isLoading else { return }

        switch step {
        case .server:
            submitServer()
        case .credentials:
            submitCredentials()
        case .library:
            submitLibrary()
        }
    }

    private func submitServer() {
        let candidates = ServerURL.candidates(from: serverStep.address)
        guard !candidates.isEmpty else {
            serverStep.isInvalid = true
            showError(JellyfinError.invalidServerURL.localizedDescription)
            return
        }

        setError(nil)
        setLoading(true)
        probe(candidates, index: 0) { [weak self] result in
            guard let self = self else { return }
            self.setLoading(false)

            switch result {
            case .success(let (url, info)):
                self.baseURL = url
                self.serverName = info.serverName
                self.reachedStep = .credentials
                self.move(to: .credentials)
            case .failure(let error):
                self.serverStep.isInvalid = true
                self.showError(error.localizedDescription)
            }
        }
    }

    private func probe(_ candidates: [URL],
                       index: Int,
                       completion: @escaping (Result<(URL, PublicSystemInfo), JellyfinError>) -> Void) {
        let url = candidates[index]
        services.client.publicSystemInfo(baseURL: url) { [weak self] result in
            switch result {
            case .success(let info):
                completion(.success((url, info)))
            case .failure(let error):
                let next = index + 1
                if next < candidates.count {
                    self?.probe(candidates, index: next, completion: completion)
                } else {
                    completion(.failure(error))
                }
            }
        }
    }

    private func submitCredentials() {
        guard let baseURL = baseURL else { return }

        let username = credentialsStep.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = credentialsStep.password
        guard !username.isEmpty else {
            credentialsStep.isInvalid = true
            showError("Enter your username.")
            return
        }

        setError(nil)
        setLoading(true)
        view.endEditing(true)

        services.client.authenticate(baseURL: baseURL, username: username, password: password) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let authentication):
                let status = self.services.signIn(with: authentication, baseURL: baseURL)
                guard status == errSecSuccess else {
                    self.setLoading(false)
                    self.showError(JellyfinError.credentialStorage(status).localizedDescription)
                    return
                }
                self.loadLibraries()
            case .failure(let error):
                self.setLoading(false)
                self.credentialsStep.isInvalid = true
                self.showError(error.localizedDescription)
            }
        }
    }

    private func loadLibraries() {
        services.client.libraries { [weak self] result in
            guard let self = self else { return }
            self.setLoading(false)

            switch result {
            case .success(let libraries):
                let photos = libraries.filter { $0.holdsPhotos }
                self.libraryStep.setLibraries(photos.isEmpty ? libraries : photos)
                self.reachedStep = .library
                self.move(to: .library)
            case .failure(let error):
                self.showError(error.localizedDescription)
            }
        }
    }

    private func submitLibrary() {
        guard let library = libraryStep.selected else { return }
        Preferences.libraryId = library.id
        Preferences.libraryName = library.name
        onFinished?()
    }

    @objc private func themeDidChange() {
        applyPalette()
        renderStep(animated: false)
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = palette.background
        card.fillColor = palette.surface
        card.applyShadow(palette)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.textColor = palette.textSecondary
        errorLabel.textColor = palette.danger
        view.applyThemeRecursively(palette)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let info = notification.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

        let overlap = max(0, view.bounds.height - view.convert(frame, from: nil).origin.y)
        keyboardHeight = overlap

        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 0

        view.layoutIfNeeded()
        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState],
                       animations: {
                        self.updateCardOffset()
                        self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }

    private func updateCardOffset() {
        let height = view.bounds.height
        let visible = height - keyboardHeight
        var offset = (visible - ConnectViewController.indicatorSpace) / 2 - height / 2

        let cardTop = height / 2 + offset - card.bounds.height / 2
        let minimumTop = view.safeAreaInsets.top + 24
        if cardTop < minimumTop {
            offset += minimumTop - cardTop
        }

        guard abs(cardCenterY.constant - offset) > 0.5 else { return }
        cardCenterY.constant = offset
    }
}

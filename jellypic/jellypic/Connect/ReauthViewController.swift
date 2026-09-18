import UIKit

final class ReauthViewController: CardSheetViewController {

    private let services: AppServices
    private let session: JellyfinSession

    private let heading = UIStackView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    private let usernameInput = TextInputView()
    private let passwordInput = TextInputView()
    private let errorLabel = UILabel()
    private let signInButton = ActionButton()

    private var keyboardOverlap: CGFloat = 0
    private var isDismissing = false

    var onSignedIn: (() -> Void)?

    init(services: AppServices, session: JellyfinSession) {
        self.services = services
        self.session = session
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
        buildHierarchy()
        applyPalette()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification,
                                               object: nil)
    }

    override func dismissCard() {
        isDismissing = true
        view.endEditing(true)
        super.dismissCard()
    }

    private func buildHierarchy() {
        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.text = "Session expired"

        subtitleLabel.font = Typography.caption
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = subtitleText()

        heading.axis = .vertical
        heading.spacing = 8
        heading.addArrangedSubview(titleLabel)
        heading.addArrangedSubview(subtitleLabel)
        setHeaderView(heading)

        usernameInput.setPlaceholder("Username")
        usernameInput.textField.text = session.username
        usernameInput.textField.autocapitalizationType = .none
        usernameInput.textField.autocorrectionType = .no
        usernameInput.textField.returnKeyType = .next
        usernameInput.textField.delegate = self
        usernameInput.isHidden = session.username != nil

        passwordInput.setPlaceholder("Password")
        passwordInput.textField.isSecureTextEntry = true
        passwordInput.textField.returnKeyType = .go
        passwordInput.textField.delegate = self

        errorLabel.font = Typography.caption
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        body.addArrangedSubview(usernameInput)
        body.addArrangedSubview(passwordInput)
        body.addArrangedSubview(errorLabel)

        signInButton.title = "Sign in"
        signInButton.addTarget(self, action: #selector(submit), for: .touchUpInside)
        footer.addArrangedSubview(signInButton)
        footer.isHidden = false
    }

    private func subtitleText() -> String {
        let host = session.baseURL.host ?? session.baseURL.absoluteString
        let account = session.username.map { "as \($0) " } ?? ""
        let indexed = services.store.count()
        guard indexed > 0 else {
            return "\(host) no longer accepts the saved session. Sign in again \(account)to keep browsing."
        }
        return "\(host) no longer accepts the saved session. Sign in again \(account)to keep browsing — the \(indexed) photos already indexed on this device stay where they are."
    }

    @objc private func submit() {
        guard !signInButton.isLoading else { return }

        let username = (usernameInput.textField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else {
            usernameInput.isInvalid = true
            showError("Enter your username.")
            return
        }

        showError(nil)
        signInButton.isLoading = true
        view.endEditing(true)

        let baseURL = session.baseURL
        services.client.authenticate(baseURL: baseURL,
                                     username: username,
                                     password: passwordInput.textField.text ?? "") { [weak self] result in
            guard let self = self else { return }
            self.signInButton.isLoading = false

            switch result {
            case .success(let authentication):
                self.completeSignIn(with: authentication, baseURL: baseURL)
            case .failure(let error):
                self.passwordInput.isInvalid = true
                self.showError(error.localizedDescription)
            }
        }
    }

    private func completeSignIn(with authentication: AuthenticationResult, baseURL: URL) {
        guard authentication.user.id == session.userId else {
            usernameInput.isInvalid = true
            showError("That is a different account. Sign in with the one that indexed this library, or sign out to start over.")
            return
        }

        let status = services.signIn(with: authentication, baseURL: baseURL)
        guard status == errSecSuccess else {
            showError(JellyfinError.credentialStorage(status).localizedDescription)
            return
        }

        dismissCard()
        onSignedIn?()
    }

    private func showError(_ message: String?) {
        errorLabel.text = message
        errorLabel.isHidden = message == nil
        guard message == nil else { return }
        usernameInput.isInvalid = false
        passwordInput.isInvalid = false
    }

    private func applyPalette() {
        let palette = Theme.palette
        applySheetPalette(palette)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.textColor = palette.textSecondary
        errorLabel.textColor = palette.danger
        view.applyThemeRecursively(palette)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard !isDismissing,
              let info = notification.userInfo,
              let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }

        let overlap = max(0, view.bounds.height - view.convert(frame, from: nil).origin.y)
        keyboardOverlap = isFullSheet ? 0 : overlap

        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt) ?? 0

        UIView.animate(withDuration: duration,
                       delay: 0,
                       options: [UIView.AnimationOptions(rawValue: curve << 16), .beginFromCurrentState],
                       animations: {
                        self.card.transform = CGAffineTransform(translationX: 0,
                                                                y: -self.keyboardOverlap)
                       },
                       completion: nil)
    }
}

extension ReauthViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameInput.textField {
            passwordInput.textField.becomeFirstResponder()
        } else {
            submit()
        }
        return false
    }
}

import UIKit

final class CredentialsStepView: UIView {

    private let usernameInput = TextInputView()
    private let passwordInput = TextInputView()

    var onSubmit: (() -> Void)?

    var username: String {
        return usernameInput.textField.text ?? ""
    }

    var password: String {
        return passwordInput.textField.text ?? ""
    }

    var isInvalid: Bool = false {
        didSet {
            usernameInput.isInvalid = isInvalid
            passwordInput.isInvalid = isInvalid
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        usernameInput.setPlaceholder("Username")
        usernameInput.textField.keyboardType = .default
        usernameInput.textField.autocapitalizationType = .none
        usernameInput.textField.autocorrectionType = .no
        usernameInput.textField.returnKeyType = .next
        usernameInput.textField.delegate = self
        usernameInput.translatesAutoresizingMaskIntoConstraints = false
        addSubview(usernameInput)

        passwordInput.setPlaceholder("Password")
        passwordInput.textField.isSecureTextEntry = true
        passwordInput.textField.autocapitalizationType = .none
        passwordInput.textField.autocorrectionType = .no
        passwordInput.textField.returnKeyType = .go
        passwordInput.textField.delegate = self
        passwordInput.translatesAutoresizingMaskIntoConstraints = false
        addSubview(passwordInput)

        NSLayoutConstraint.activate([
            usernameInput.topAnchor.constraint(equalTo: topAnchor),
            usernameInput.leadingAnchor.constraint(equalTo: leadingAnchor),
            usernameInput.trailingAnchor.constraint(equalTo: trailingAnchor),

            passwordInput.topAnchor.constraint(equalTo: usernameInput.bottomAnchor, constant: 10),
            passwordInput.leadingAnchor.constraint(equalTo: leadingAnchor),
            passwordInput.trailingAnchor.constraint(equalTo: trailingAnchor),
            passwordInput.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func focus() {
        usernameInput.textField.becomeFirstResponder()
    }
}

extension CredentialsStepView: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameInput.textField {
            passwordInput.textField.becomeFirstResponder()
        } else {
            onSubmit?()
        }
        return false
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        isInvalid = false
        return true
    }
}

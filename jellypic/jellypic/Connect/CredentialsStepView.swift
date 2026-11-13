import UIKit

final class CredentialsStepView: UIView {

    private let fields = GroupedInputView()

    var onSubmit: (() -> Void)?

    var username: String {
        return fields.topField.text ?? ""
    }

    var password: String {
        return fields.bottomField.text ?? ""
    }

    var isInvalid: Bool = false {
        didSet {
            fields.isInvalid = isInvalid
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        fields.setPlaceholders(top: "Username", bottom: "Password")

        fields.topField.keyboardType = .default
        fields.topField.textContentType = .username
        fields.topField.autocapitalizationType = .none
        fields.topField.autocorrectionType = .no
        fields.topField.returnKeyType = .next
        fields.topField.delegate = self

        fields.bottomField.isSecureTextEntry = true
        fields.bottomField.textContentType = .password
        fields.bottomField.autocapitalizationType = .none
        fields.bottomField.autocorrectionType = .no
        fields.bottomField.returnKeyType = .go
        fields.bottomField.delegate = self

        fields.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fields)

        NSLayoutConstraint.activate([
            fields.topAnchor.constraint(equalTo: topAnchor),
            fields.leadingAnchor.constraint(equalTo: leadingAnchor),
            fields.trailingAnchor.constraint(equalTo: trailingAnchor),
            fields.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func focus() {
        fields.topField.becomeFirstResponder()
    }
}

extension CredentialsStepView: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === fields.topField {
            fields.bottomField.becomeFirstResponder()
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

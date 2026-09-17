import UIKit

final class ServerStepView: UIView, Themed {

    private let input = TextInputView()
    private let hintLabel = UILabel()

    var onSubmit: (() -> Void)?

    var address: String {
        return input.textField.text ?? ""
    }

    var isInvalid: Bool = false {
        didSet { input.isInvalid = isInvalid }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        input.setPlaceholder("192.168.1.10")
        input.textField.keyboardType = .URL
        input.textField.autocapitalizationType = .none
        input.textField.autocorrectionType = .no
        input.textField.returnKeyType = .continue
        input.textField.delegate = self
        input.translatesAutoresizingMaskIntoConstraints = false
        addSubview(input)

        hintLabel.text = "Port 8096 is tried automatically if you leave it out."
        hintLabel.font = Typography.caption
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.numberOfLines = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            input.topAnchor.constraint(equalTo: topAnchor),
            input.leadingAnchor.constraint(equalTo: leadingAnchor),
            input.trailingAnchor.constraint(equalTo: trailingAnchor),

            hintLabel.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 10),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            hintLabel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func focus() {
        input.textField.becomeFirstResponder()
    }

    func applyTheme(_ palette: ThemePalette) {
        hintLabel.textColor = palette.textSecondary
    }
}

extension ServerStepView: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onSubmit?()
        return false
    }

    func textField(_ textField: UITextField,
                   shouldChangeCharactersIn range: NSRange,
                   replacementString string: String) -> Bool {
        isInvalid = false
        return true
    }
}

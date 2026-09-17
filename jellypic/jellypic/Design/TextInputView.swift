import UIKit

final class TextInputView: UIView, Themed {

    let textField = UITextField()

    private let background = SquircleView()
    private var palette = Theme.palette

    var isInvalid: Bool = false {
        didSet { refresh() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        background.cornerRadius = 14
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        textField.font = Typography.body
        textField.adjustsFontForContentSizeCategory = true
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        textField.textColor = palette.textPrimary
        textField.keyboardAppearance = Theme.isDark ? .dark : .light
        refresh()
    }

    func setPlaceholder(_ text: String) {
        textField.attributedPlaceholder = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: palette.textSecondary]
        )
    }

    private func refresh() {
        background.fillColor = palette.field
        background.strokeColor = isInvalid ? palette.danger : .clear
        background.strokeWidth = isInvalid ? 1.5 : 0
        if let placeholder = textField.attributedPlaceholder?.string {
            setPlaceholder(placeholder)
        }
    }
}

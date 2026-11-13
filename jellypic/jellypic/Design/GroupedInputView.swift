import UIKit

final class GroupedInputView: UIView, Themed {

    static let rowHeight: CGFloat = 48

    let topField = UITextField()
    let bottomField = UITextField()

    private let background = SquircleView()
    private let separator = UIView()
    private var palette = Theme.palette

    var isInvalid: Bool = false {
        didSet { refresh() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        background.cornerRadius = 14
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        for field in [topField, bottomField] {
            field.font = Typography.body
            field.adjustsFontForContentSizeCategory = true
            field.clearButtonMode = .whileEditing
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }

        separator.isUserInteractionEnabled = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            topField.topAnchor.constraint(equalTo: topAnchor),
            topField.heightAnchor.constraint(equalToConstant: GroupedInputView.rowHeight),
            topField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            topField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            separator.topAnchor.constraint(equalTo: topField.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            bottomField.topAnchor.constraint(equalTo: separator.bottomAnchor),
            bottomField.heightAnchor.constraint(equalToConstant: GroupedInputView.rowHeight),
            bottomField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bottomField.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        for field in [topField, bottomField] {
            field.textColor = palette.textPrimary
            field.keyboardAppearance = Theme.isDark ? .dark : .light
        }
        refresh()
    }

    func setPlaceholders(top: String, bottom: String) {
        topField.attributedPlaceholder = placeholder(top)
        bottomField.attributedPlaceholder = placeholder(bottom)
    }

    private func placeholder(_ text: String) -> NSAttributedString {
        return NSAttributedString(string: text, attributes: [.foregroundColor: palette.textSecondary])
    }

    private func refresh() {
        background.fillColor = palette.field
        background.strokeColor = isInvalid ? palette.danger : .clear
        background.strokeWidth = isInvalid ? 1.5 : 0
        separator.backgroundColor = palette.hairline
        for field in [topField, bottomField] {
            if let text = field.attributedPlaceholder?.string {
                field.attributedPlaceholder = placeholder(text)
            }
        }
    }
}

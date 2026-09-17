import UIKit

final class OptionRowView: UIControl, Themed {

    private let background = SquircleView()
    private let titleLabel = UILabel()
    private let indicator = SelectionIndicatorView()
    private var palette = Theme.palette

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var isOn: Bool = false {
        didSet {
            indicator.isOn = isOn
            refresh()
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.7 : 1 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        background.cornerRadius = 14
        background.isUserInteractionEnabled = false
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        titleLabel.font = Typography.body
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        indicator.isUserInteractionEnabled = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicator)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: topAnchor),
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: indicator.leadingAnchor, constant: -12),

            indicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicator.widthAnchor.constraint(equalToConstant: 24),
            indicator.heightAnchor.constraint(equalToConstant: 24)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        titleLabel.textColor = palette.textPrimary
        indicator.applyTheme(palette)
        refresh()
    }

    private func refresh() {
        background.fillColor = isOn ? palette.field : .clear
    }
}

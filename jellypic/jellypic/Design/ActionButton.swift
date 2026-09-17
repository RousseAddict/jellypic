import UIKit

final class ActionButton: UIControl, Themed {

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    private let titleLabel = UILabel()
    // LEGACY(ios12): UIActivityIndicatorView.Style.medium is iOS 13+; .white is the only option here. Freed at iOS 13.
    private let spinner = UIActivityIndicatorView(style: .white)
    private var palette = Theme.palette

    var title: String = "" {
        didSet { titleLabel.text = title }
    }

    var isLoading: Bool = false {
        didSet {
            guard isLoading != oldValue else { return }
            titleLabel.alpha = isLoading ? 0 : 1
            if isLoading {
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
            }
            isEnabled = !isLoading
        }
    }

    override var isEnabled: Bool {
        didSet { refresh() }
    }

    override var isHighlighted: Bool {
        didSet { refreshHighlight() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        titleLabel.font = Typography.button
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        addSubview(spinner)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = Squircle.path(in: bounds, cornerRadius: 16).cgPath
        shapeLayer.path = path
        shapeLayer.shadowPath = path
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        titleLabel.textColor = palette.onAccent
        spinner.color = palette.onAccent
        refresh()
    }

    private func refresh() {
        shapeLayer.fillColor = isEnabled
            ? palette.accent.cgColor
            : palette.accent.withAlphaComponent(0.25).cgColor
    }

    private func refreshHighlight() {
        let scale: CGFloat = isHighlighted ? 0.97 : 1
        UIView.animate(withDuration: 0.16,
                       delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: {
                        self.transform = CGAffineTransform(scaleX: scale, y: scale)
                       },
                       completion: nil)
    }
}

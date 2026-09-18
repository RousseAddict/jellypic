import UIKit

final class SyncBannerView: UIView, Themed {

    private let surface = SquircleView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .white)

    private var spinnerWidth: NSLayoutConstraint!
    private var spinnerGap: NSLayoutConstraint!

    var onTap: (() -> Void)?

    var isBusy: Bool = true {
        didSet {
            guard isBusy != oldValue else { return }
            spinner.isHidden = !isBusy
            if isBusy {
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
            }
            spinnerWidth.constant = isBusy ? 14 : 0
            spinnerGap.constant = isBusy ? 8 : 0
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        spinner.hidesWhenStopped = false
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(spinner)

        label.font = Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(label)

        spinnerWidth = spinner.widthAnchor.constraint(equalToConstant: 14)
        spinnerGap = label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            spinnerWidth,
            spinner.heightAnchor.constraint(equalToConstant: 14),

            spinnerGap,
            label.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: surface.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -8)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.cornerRadius = bounds.height / 2
    }

    var text: String? {
        get { return label.text }
        set { label.text = newValue }
    }

    @objc private func handleTap() {
        onTap?()
    }

    func applyTheme(_ palette: ThemePalette) {
        surface.fillColor = palette.surface
        surface.applyShadow(palette)
        label.textColor = palette.textSecondary
        // LEGACY(ios12): UIActivityIndicatorView.Style.medium is iOS 13+, so the colour is set rather than the style. Freed at iOS 13.
        spinner.color = palette.textSecondary
    }
}

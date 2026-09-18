import UIKit

final class SyncBannerView: UIView, Themed {

    private let surface = SquircleView()
    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .white)

    override init(frame: CGRect) {
        super.init(frame: frame)

        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        spinner.hidesWhenStopped = false
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(spinner)

        label.font = Typography.caption
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(label)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            spinner.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 14),
            spinner.heightAnchor.constraint(equalToConstant: 14),

            label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
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

    func applyTheme(_ palette: ThemePalette) {
        surface.fillColor = palette.surface
        surface.applyShadow(palette)
        label.textColor = palette.textSecondary
        // LEGACY(ios12): UIActivityIndicatorView.Style.medium is iOS 13+, so the colour is set rather than the style.
        spinner.color = palette.textSecondary
    }
}

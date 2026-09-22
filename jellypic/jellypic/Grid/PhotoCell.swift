import UIKit

enum GridMetrics {

    static let spacing: CGFloat = 1

    private static let targetSide: CGFloat = 118
    private static let minimumColumns: CGFloat = 3
    private static let pixelStep = 64

    static func itemSide(forWidth width: CGFloat) -> CGFloat {
        let columns = max(minimumColumns, (width / targetSide).rounded())
        return floor((width - spacing * (columns - 1)) / columns)
    }

    static func thumbnailPixels(for side: CGFloat) -> Int {
        let exact = Int((side * UIScreen.main.scale).rounded(.up))
        return (exact + pixelStep - 1) / pixelStep * pixelStep
    }
}

enum DurationBadge {

    static func text(for seconds: Double) -> String {
        guard seconds > 0 else { return "–" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total / 60) % 60
        let remainder = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}

final class PhotoCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoCell"

    private static let badgeInset: CGFloat = 4
    private static let scrimHeight: CGFloat = 28

    private let imageView = UIImageView()
    private let scrim = CAGradientLayer()
    private let durationLabel = UILabel()
    private var task: URLSessionTask?
    private var token: String = ""

    var image: UIImage? {
        return imageView.image
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(imageView)
        contentView.clipsToBounds = true

        scrim.colors = [UIColor.black.withAlphaComponent(0).cgColor,
                        UIColor.black.withAlphaComponent(0.45).cgColor]
        scrim.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        scrim.isHidden = true
        contentView.layer.addSublayer(scrim)

        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right
        durationLabel.isHidden = true
        contentView.addSubview(durationLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        scrim.frame = CGRect(x: 0,
                             y: bounds.height - PhotoCell.scrimHeight,
                             width: bounds.width,
                             height: PhotoCell.scrimHeight)
        let lineHeight = durationLabel.font.lineHeight.rounded(.up)
        durationLabel.frame = CGRect(x: PhotoCell.badgeInset,
                                     y: bounds.height - lineHeight - PhotoCell.badgeInset,
                                     width: max(0, bounds.width - PhotoCell.badgeInset * 2),
                                     height: lineHeight)
    }

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted ? 0.7 : 1 }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        token = ""
        imageView.image = nil
        imageView.alpha = 1
        durationLabel.isHidden = true
        scrim.isHidden = true
        isHidden = false
    }

    func configure(itemId: String,
                   tag: String?,
                   pixels: Int,
                   duration: Double?,
                   placeholder: UIColor,
                   loader: ImageLoader) {
        contentView.backgroundColor = placeholder
        token = itemId

        if let duration = duration {
            durationLabel.text = DurationBadge.text(for: duration)
            durationLabel.isHidden = false
            scrim.isHidden = false
        }

        if let hit = loader.cached(itemId: itemId, tag: tag, pixels: pixels) {
            imageView.image = hit
            return
        }

        task = loader.load(itemId: itemId, tag: tag, pixels: pixels) { [weak self] image in
            guard let self = self, self.token == itemId, let image = image else { return }
            self.imageView.image = image
            self.imageView.alpha = 0
            UIView.animate(withDuration: 0.18) { self.imageView.alpha = 1 }
        }
    }
}

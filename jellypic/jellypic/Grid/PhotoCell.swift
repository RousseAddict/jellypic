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

final class PhotoCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoCell"

    private let imageView = UIImageView()
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
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
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
        isHidden = false
    }

    func configure(itemId: String,
                   tag: String?,
                   pixels: Int,
                   placeholder: UIColor,
                   loader: ImageLoader) {
        contentView.backgroundColor = placeholder
        token = itemId

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

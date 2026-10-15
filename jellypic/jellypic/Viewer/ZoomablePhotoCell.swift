import UIKit

private final class RetryPillButton: UIControl {

    private let surface = SquircleView()
    private let titleLabel = UILabel()

    init(title: String) {
        super.init(frame: .zero)

        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        titleLabel.text = title
        titleLabel.font = Typography.button
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.isUserInteractionEnabled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94)
                    : .identity
            }
        }
    }

    func apply(_ palette: ThemePalette) {
        surface.fillColor = palette.surface
        surface.applyShadow(palette)
        titleLabel.textColor = palette.textPrimary
    }
}

final class ZoomablePhotoCell: UICollectionViewCell, UIScrollViewDelegate {

    static let reuseIdentifier = "ZoomablePhotoCell"
    static let gap: CGFloat = 20

    private static let glyphInk = UIColor(white: 1, alpha: 0.45)
    private static let messageInk = UIColor(white: 1, alpha: 0.75)
    private static let failureGlyphSide: CGFloat = 44

    let imageView = UIImageView()

    private let scrollView = UIScrollView()
    private let failureStack = UIStackView()
    private let failureGlyph = BrokenImageGlyphView()
    private let failureLabel = UILabel()
    private let retryButton = RetryPillButton(title: "Retry")

    private var task: URLSessionTask?
    private var token = ""
    private var laidOutSize = CGSize.zero

    private var imageTag: String?
    private var thumbnailPixels = 0
    private var fullPixels = 0
    private weak var loader: ImageLoader?

    var onSingleTap: (() -> Void)?

    var isZoomed: Bool {
        return scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.contentInsetAdjustmentBehavior = .never
        contentView.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)

        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        double.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(double)

        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)

        failureGlyph.color = ZoomablePhotoCell.glyphInk
        failureGlyph.translatesAutoresizingMaskIntoConstraints = false

        failureLabel.font = Typography.caption
        failureLabel.adjustsFontForContentSizeCategory = true
        failureLabel.textColor = ZoomablePhotoCell.messageInk
        failureLabel.textAlignment = .center
        failureLabel.numberOfLines = 0

        retryButton.addTarget(self, action: #selector(retry), for: .touchUpInside)

        failureStack.axis = .vertical
        failureStack.alignment = .center
        failureStack.spacing = 16
        failureStack.isHidden = true
        failureStack.translatesAutoresizingMaskIntoConstraints = false
        failureStack.addArrangedSubview(failureGlyph)
        failureStack.addArrangedSubview(failureLabel)
        failureStack.addArrangedSubview(retryButton)
        failureStack.setCustomSpacing(12, after: failureGlyph)
        contentView.addSubview(failureStack)

        NSLayoutConstraint.activate([
            failureGlyph.widthAnchor.constraint(equalToConstant: ZoomablePhotoCell.failureGlyphSide),
            failureGlyph.heightAnchor.constraint(equalToConstant: ZoomablePhotoCell.failureGlyphSide),

            failureStack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            failureStack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            failureStack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor,
                                                  constant: 40),
            failureStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor,
                                                   constant: -40)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = contentView.bounds.insetBy(dx: ZoomablePhotoCell.gap / 2, dy: 0)
        guard scrollView.bounds.size != laidOutSize else { return }
        laidOutSize = scrollView.bounds.size
        layoutImage()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        token = ""
        scrollView.zoomScale = 1
        imageView.image = nil
        laidOutSize = .zero
        failureStack.isHidden = true
        imageTag = nil
        thumbnailPixels = 0
        fullPixels = 0
        loader = nil
    }

    func configure(itemId: String,
                   tag: String?,
                   thumbnailPixels: Int,
                   fullPixels: Int,
                   loader: ImageLoader) {
        token = itemId
        imageTag = tag
        self.thumbnailPixels = thumbnailPixels
        self.fullPixels = fullPixels
        self.loader = loader

        failureStack.isHidden = true
        retryButton.apply(Theme.palette)

        if let thumbnail = loader.cached(itemId: itemId, tag: tag, pixels: thumbnailPixels) {
            imageView.image = thumbnail
            layoutImage()
        }

        task = loader.loadFull(itemId: itemId, tag: tag, maxPixels: fullPixels) { [weak self] result in
            guard let self = self, self.token == itemId else { return }
            switch result {
            case .image(let image):
                let wasZoomed = self.isZoomed
                self.imageView.image = image
                guard !wasZoomed else { return }
                self.layoutImage()
            case .failed(let message):
                guard self.imageView.image == nil else { return }
                self.failureLabel.text = message
                self.failureStack.isHidden = false
            case .deferred:
                break
            }
        }
    }

    @objc private func retry() {
        guard let loader = loader, !token.isEmpty else { return }
        configure(itemId: token,
                  tag: imageTag,
                  thumbnailPixels: thumbnailPixels,
                  fullPixels: fullPixels,
                  loader: loader)
    }

    private func layoutImage() {
        guard let image = imageView.image else { return }
        let bounds = scrollView.bounds.size
        guard bounds.width > 0, bounds.height > 0,
              image.size.width > 0, image.size.height > 0 else { return }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        scrollView.zoomScale = 1
        imageView.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        centerImage()
    }

    private func centerImage() {
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        let horizontal = max(0, (bounds.width - content.width) / 2)
        let vertical = max(0, (bounds.height - content.height) / 2)
        scrollView.contentInset = UIEdgeInsets(top: vertical,
                                               left: horizontal,
                                               bottom: vertical,
                                               right: horizontal)
    }

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !isZoomed else {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            return
        }
        let scale: CGFloat = 2.5
        let point = gesture.location(in: imageView)
        let size = CGSize(width: scrollView.bounds.width / scale,
                          height: scrollView.bounds.height / scale)
        scrollView.zoom(to: CGRect(x: point.x - size.width / 2,
                                   y: point.y - size.height / 2,
                                   width: size.width,
                                   height: size.height),
                        animated: true)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }
}

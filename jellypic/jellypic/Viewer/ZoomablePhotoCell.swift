import UIKit

final class ZoomablePhotoCell: UICollectionViewCell, UIScrollViewDelegate {

    static let reuseIdentifier = "ZoomablePhotoCell"
    static let gap: CGFloat = 20

    let imageView = UIImageView()

    private let scrollView = UIScrollView()
    private var task: URLSessionTask?
    private var token = ""
    private var laidOutSize = CGSize.zero

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
    }

    func configure(itemId: String,
                   tag: String?,
                   thumbnailPixels: Int,
                   fullPixels: Int,
                   loader: ImageLoader) {
        token = itemId

        if let thumbnail = loader.cached(itemId: itemId, tag: tag, pixels: thumbnailPixels) {
            imageView.image = thumbnail
            layoutImage()
        }

        task = loader.loadFull(itemId: itemId, tag: tag, maxPixels: fullPixels) { [weak self] image in
            guard let self = self, self.token == itemId, let image = image else { return }
            let wasZoomed = self.isZoomed
            self.imageView.image = image
            guard !wasZoomed else { return }
            self.layoutImage()
        }
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

import MapKit
import UIKit

final class PhotoMarkerView: MKAnnotationView {

    static let reuseIdentifier = "PhotoMarker"
    static let thumbnailPixels = 128

    private static let singleSide: CGFloat = 44
    private static let clusterSide: CGFloat = 56
    private static let cornerRadius: CGFloat = 12
    private static let borderWidth: CGFloat = 2
    private static let badgeHeight: CGFloat = 18

    private let border = UIView()
    private let imageView = UIImageView()
    private let badge = UILabel()
    private var task: URLSessionTask?
    private var token = ""

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        let palette = Theme.palette

        border.backgroundColor = palette.surface
        border.layer.cornerRadius = PhotoMarkerView.cornerRadius
        border.layer.shadowColor = palette.shadowColor.cgColor
        border.layer.shadowOpacity = 0.25
        border.layer.shadowRadius = 4
        border.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(border)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = palette.field
        imageView.layer.cornerRadius = PhotoMarkerView.cornerRadius - PhotoMarkerView.borderWidth
        border.addSubview(imageView)

        badge.textAlignment = .center
        badge.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = palette.onAccent
        badge.backgroundColor = palette.accent
        badge.layer.cornerRadius = PhotoMarkerView.badgeHeight / 2
        badge.layer.masksToBounds = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        task?.cancel()
        task = nil
        token = ""
        imageView.image = nil
    }

    func configure(with cluster: PhotoCluster, loader: ImageLoader) {
        let side = cluster.count > 1 ? PhotoMarkerView.clusterSide : PhotoMarkerView.singleSide
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        border.frame = bounds
        imageView.frame = bounds.insetBy(dx: PhotoMarkerView.borderWidth,
                                         dy: PhotoMarkerView.borderWidth)
        layoutBadge(count: cluster.count, side: side)

        let photo = cluster.photo
        token = photo.id

        if let hit = loader.cached(itemId: photo.id,
                                   tag: photo.imageTag,
                                   pixels: PhotoMarkerView.thumbnailPixels) {
            imageView.image = hit
            return
        }

        task = loader.load(itemId: photo.id,
                           tag: photo.imageTag,
                           pixels: PhotoMarkerView.thumbnailPixels) { [weak self] image in
            guard let self = self, self.token == photo.id, let image = image else { return }
            self.imageView.image = image
            self.imageView.alpha = 0
            UIView.animate(withDuration: 0.18) { self.imageView.alpha = 1 }
        }
    }

    private func layoutBadge(count: Int, side: CGFloat) {
        guard count > 1 else {
            badge.isHidden = true
            return
        }

        badge.isHidden = false
        badge.text = count > 999 ? "999+" : "\(count)"

        let width = max(PhotoMarkerView.badgeHeight, badge.intrinsicContentSize.width + 10)
        badge.frame = CGRect(x: side - width + 5,
                             y: -5,
                             width: width,
                             height: PhotoMarkerView.badgeHeight)
    }
}

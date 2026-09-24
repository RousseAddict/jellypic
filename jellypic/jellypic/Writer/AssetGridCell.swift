import Photos
import UIKit

final class AssetGridCell: UICollectionViewCell {

    static let reuseIdentifier = "AssetGridCell"

    private static let badgeSide: CGFloat = 22
    private static let badgeInset: CGFloat = 4
    private static let selectionInset: CGFloat = 6

    private let content = UIView()
    private let imageView = UIImageView()
    private let indicator = SelectionIndicatorView()

    private var identifier = ""
    private var requestId = PHInvalidImageRequestID
    private weak var manager: PHImageManager?
    private var isChosen = false

    override init(frame: CGRect) {
        super.init(frame: frame)

        content.clipsToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(content)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(imageView)

        indicator.isHidden = true
        indicator.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(indicator)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.topAnchor.constraint(equalTo: content.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            indicator.widthAnchor.constraint(equalToConstant: AssetGridCell.badgeSide),
            indicator.heightAnchor.constraint(equalToConstant: AssetGridCell.badgeSide),
            indicator.trailingAnchor.constraint(equalTo: content.trailingAnchor,
                                                constant: -AssetGridCell.badgeInset),
            indicator.bottomAnchor.constraint(equalTo: content.bottomAnchor,
                                              constant: -AssetGridCell.badgeInset)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applySelectionScale()
    }

    override var isHighlighted: Bool {
        didSet { imageView.alpha = isHighlighted ? 0.7 : 1 }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if requestId != PHInvalidImageRequestID {
            manager?.cancelImageRequest(requestId)
            requestId = PHInvalidImageRequestID
        }
        identifier = ""
        imageView.image = nil
        imageView.alpha = 1
        isChosen = false
        indicator.isOn = false
        indicator.isHidden = true
        content.transform = .identity
    }

    func configure(asset: PHAsset,
                   pixels: Int,
                   chosen: Bool,
                   palette: ThemePalette,
                   manager: PHCachingImageManager,
                   options: PHImageRequestOptions) {
        content.backgroundColor = palette.field
        indicator.applyTheme(palette)
        identifier = asset.localIdentifier
        setChosen(chosen, animated: false)

        self.manager = manager
        requestId = manager.requestImage(for: asset,
                                         targetSize: CGSize(width: pixels, height: pixels),
                                         contentMode: .aspectFill,
                                         options: options) { [weak self] image, _ in
            guard let self = self,
                  self.identifier == asset.localIdentifier,
                  let image = image else { return }
            self.imageView.image = image
        }
    }

    func setChosen(_ chosen: Bool, animated: Bool) {
        isChosen = chosen
        indicator.isHidden = !chosen
        indicator.isOn = chosen

        guard animated else {
            applySelectionScale()
            return
        }
        UIView.animate(withDuration: 0.14,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: { self.applySelectionScale() },
                       completion: nil)
    }

    private func applySelectionScale() {
        let side = bounds.width
        guard side > AssetGridCell.selectionInset * 2 else { return }
        let scale = isChosen ? (side - AssetGridCell.selectionInset * 2) / side : 1
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

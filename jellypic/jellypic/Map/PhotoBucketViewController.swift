import UIKit

final class PhotoBucketViewController: UIViewController {

    private static let chromeInset: CGFloat = 56

    private let services: AppServices
    private let timeline: PhotoListTimeline

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let closeButton = FloatingButton(glyph: CloseGlyphView())
    private let titlePill = SquircleView()
    private let titleLabel = UILabel()

    private var thumbnailPixels = 0
    private var transitionIndexPath: IndexPath?
    private weak var hiddenCell: PhotoCell?

    init(services: AppServices, photos: [Photo]) {
        self.services = services
        self.timeline = PhotoListTimeline(photos: photos)
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateItemSize()
    }

    private func buildHierarchy() {
        let palette = Theme.palette
        view.backgroundColor = palette.background

        layout.minimumInteritemSpacing = GridMetrics.spacing
        layout.minimumLineSpacing = GridMetrics.spacing

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.alwaysBounceVertical = true
        collectionView.contentInsetAdjustmentBehavior = .always
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)

        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        titlePill.cornerRadius = 15
        titlePill.fillColor = palette.surface
        titlePill.applyShadow(palette)
        titlePill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titlePill)

        titleLabel.font = Typography.caption
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = palette.textSecondary
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.text = countTitle()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlePill.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                 constant: 12),

            titlePill.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titlePill.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            titlePill.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor,
                                               constant: 12),
            titlePill.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                constant: -12),

            titleLabel.leadingAnchor.constraint(equalTo: titlePill.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: titlePill.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: titlePill.topAnchor, constant: 7),
            titleLabel.bottomAnchor.constraint(equalTo: titlePill.bottomAnchor, constant: -7)
        ])
    }

    private func countTitle() -> String {
        let count = timeline.numberOfPhotos(inSection: 0)
        return count == 1 ? "1 photo" : "\(count) photos"
    }

    private func updateItemSize() {
        let inset = max(view.safeAreaInsets.left, view.safeAreaInsets.right)
        let width = collectionView.bounds.width - inset * 2
        guard width > 0 else { return }

        let side = GridMetrics.itemSide(forWidth: width)
        guard side > 0 else { return }

        let pixels = GridMetrics.thumbnailPixels(for: side)
        guard layout.itemSize.width != side || thumbnailPixels != pixels else { return }

        layout.itemSize = CGSize(width: side, height: side)
        layout.sectionInset = UIEdgeInsets(top: PhotoBucketViewController.chromeInset,
                                           left: inset,
                                           bottom: 16,
                                           right: inset)
        layout.invalidateLayout()

        guard thumbnailPixels != pixels else { return }
        thumbnailPixels = pixels
        collectionView.reloadData()
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }
}

extension PhotoBucketViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return timeline.sectionCount
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return timeline.numberOfPhotos(inSection: section)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseIdentifier,
                                                      for: indexPath) as! PhotoCell
        let photo = timeline.photo(at: indexPath)
        cell.configure(itemId: photo.id,
                       tag: photo.imageTag,
                       pixels: thumbnailPixels,
                       placeholder: Theme.palette.field,
                       loader: services.images)
        return cell
    }
}

extension PhotoBucketViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        transitionIndexPath = indexPath

        let viewer = PhotoViewerViewController(services: services,
                                               timeline: timeline,
                                               startAt: indexPath,
                                               thumbnailPixels: thumbnailPixels)
        viewer.transitionSource = self
        viewer.onWillDismiss = { [weak self] path in
            self?.prepareForReturn(to: path)
        }
        present(viewer, animated: true, completion: nil)
    }

    private func prepareForReturn(to indexPath: IndexPath) {
        transitionIndexPath = indexPath
        guard collectionView.cellForItem(at: indexPath) == nil else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
    }
}

extension PhotoBucketViewController: ZoomTransitionEndpoint {

    private var transitionCell: PhotoCell? {
        guard let indexPath = transitionIndexPath else { return nil }
        return collectionView.cellForItem(at: indexPath) as? PhotoCell
    }

    func zoomTransitionImage() -> UIImage? {
        return transitionCell?.image
    }

    func zoomTransitionRect(in container: UIView) -> CGRect? {
        guard let cell = transitionCell, cell.image != nil else { return nil }
        return cell.convert(cell.bounds, to: container)
    }

    func zoomTransitionSetHidden(_ hidden: Bool) {
        hiddenCell?.isHidden = false
        hiddenCell = hidden ? transitionCell : nil
        hiddenCell?.isHidden = true
    }
}

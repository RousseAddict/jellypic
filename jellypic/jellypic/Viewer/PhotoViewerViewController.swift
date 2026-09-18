import UIKit
import CoreData

final class PhotoViewerViewController: UIViewController {

    private static let maximumFullPixels = 2048

    private let services: AppServices
    private let results: NSFetchedResultsController<PhotoItem>
    private let thumbnailPixels: Int
    private let fullPixels: Int

    private let backdrop = UIView()
    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let closeButton = FloatingButton(glyph: CloseGlyphView())
    private let moreButton = FloatingButton()
    private let datePill = SquircleView()
    private let dateLabel = UILabel()

    private var isChromeVisible = false
    private var laidOutSize = CGSize.zero
    private var isAdjustingLayout = false
    private var detailsCard: PhotoDetailsViewController?

    private(set) var currentIndexPath: IndexPath

    weak var transitionSource: ZoomTransitionEndpoint?
    var onWillDismiss: ((IndexPath) -> Void)?

    init(services: AppServices,
         results: NSFetchedResultsController<PhotoItem>,
         startAt indexPath: IndexPath,
         thumbnailPixels: Int) {
        self.services = services
        self.results = results
        self.thumbnailPixels = thumbnailPixels
        self.currentIndexPath = indexPath

        let screen = UIScreen.main.bounds
        let longest = max(screen.width, screen.height) * UIScreen.main.scale
        self.fullPixels = min(Int(longest) * 2, PhotoViewerViewController.maximumFullPixels)

        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        updateDateLabel()
        setChrome(visible: false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let gap = ZoomablePhotoCell.gap
        collectionView.frame = view.bounds.insetBy(dx: -gap / 2, dy: 0)

        let size = collectionView.bounds.size
        guard size.width > 0, size != laidOutSize else { return }
        laidOutSize = size

        isAdjustingLayout = true
        layout.itemSize = size
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: currentIndexPath,
                                    at: .centeredHorizontally,
                                    animated: false)
        isAdjustingLayout = false
    }

    override func viewWillTransition(to size: CGSize,
                                     with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        isAdjustingLayout = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.isAdjustingLayout = false
        }
    }

    private func buildHierarchy() {
        backdrop.backgroundColor = .black
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)

        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.isPagingEnabled = true
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ZoomablePhotoCell.self,
                                forCellWithReuseIdentifier: ZoomablePhotoCell.reuseIdentifier)
        view.addSubview(collectionView)

        datePill.cornerRadius = 15
        datePill.fillColor = Theme.palette.surface
        datePill.applyShadow(Theme.palette)
        datePill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(datePill)

        dateLabel.font = Typography.caption
        dateLabel.adjustsFontForContentSizeCategory = true
        dateLabel.textColor = Theme.palette.textSecondary
        dateLabel.lineBreakMode = .byTruncatingTail
        dateLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        datePill.addSubview(dateLabel)

        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        moreButton.addTarget(self, action: #selector(showDetails), for: .touchUpInside)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                                 constant: 12),

            moreButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            moreButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                 constant: -12),

            datePill.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            datePill.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),
            datePill.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor,
                                              constant: 12),
            datePill.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor,
                                               constant: -12),

            dateLabel.leadingAnchor.constraint(equalTo: datePill.leadingAnchor, constant: 14),
            dateLabel.trailingAnchor.constraint(equalTo: datePill.trailingAnchor, constant: -14),
            dateLabel.topAnchor.constraint(equalTo: datePill.topAnchor, constant: 7),
            dateLabel.bottomAnchor.constraint(equalTo: datePill.bottomAnchor, constant: -7)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan))
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    private var currentCell: ZoomablePhotoCell? {
        return collectionView.cellForItem(at: currentIndexPath) as? ZoomablePhotoCell
    }

    private func updateCurrentIndexPath() {
        let point = CGPoint(x: collectionView.contentOffset.x + collectionView.bounds.midX,
                            y: collectionView.bounds.midY)
        guard let path = collectionView.indexPathForItem(at: point), path != currentIndexPath else {
            return
        }
        currentIndexPath = path
        updateDateLabel()
    }

    private func updateDateLabel() {
        guard currentIndexPath.section < (results.sections?.count ?? 0) else { return }
        let item = results.object(at: currentIndexPath)
        dateLabel.text = PhotoDateFormatter.string(from: item.captureDate)
    }

    private func setChrome(visible: Bool, animated: Bool) {
        isChromeVisible = visible
        let alpha: CGFloat = visible ? 1 : 0
        guard animated else {
            closeButton.alpha = alpha
            moreButton.alpha = alpha
            datePill.alpha = alpha
            return
        }
        UIView.animate(withDuration: 0.2) {
            self.closeButton.alpha = alpha
            self.moreButton.alpha = alpha
            self.datePill.alpha = alpha
        }
    }

    @objc private func toggleChrome() {
        setChrome(visible: !isChromeVisible, animated: true)
    }

    @objc private func showDetails() {
        guard detailsCard == nil,
              currentIndexPath.section < (results.sections?.count ?? 0) else { return }
        let item = results.object(at: currentIndexPath)
        let card = PhotoDetailsViewController(services: services,
                                              itemId: item.id,
                                              displayImage: currentCell?.imageView.image)
        card.onDismissed = { [weak self] in self?.detailsCard = nil }
        detailsCard = card
        card.present(over: self)
    }

    @objc private func close() {
        dismiss(animated: true, completion: nil)
    }

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .began:
            collectionView.isScrollEnabled = false
            setChrome(visible: false, animated: true)

        case .changed:
            let progress = min(1, max(0, translation.y / (view.bounds.height * 0.6)))
            let scale = 1 - progress * 0.3
            collectionView.transform = CGAffineTransform(translationX: translation.x,
                                                         y: translation.y)
                .scaledBy(x: scale, y: scale)
            backdrop.alpha = 1 - progress * 0.7

        case .ended, .cancelled:
            collectionView.isScrollEnabled = true
            let velocity = gesture.velocity(in: view)
            if translation.y > view.bounds.height * 0.16 || velocity.y > 900 {
                dismiss(animated: true, completion: nil)
                return
            }
            UIView.animate(withDuration: 0.25,
                           delay: 0,
                           options: [.beginFromCurrentState],
                           animations: {
                            self.collectionView.transform = .identity
                            self.backdrop.alpha = 1
                           },
                           completion: nil)

        default:
            break
        }
    }
}

extension PhotoViewerViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return results.sections?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return results.sections?[section].numberOfObjects ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZoomablePhotoCell.reuseIdentifier,
                                                      for: indexPath) as! ZoomablePhotoCell
        let item = results.object(at: indexPath)
        cell.configure(itemId: item.id,
                       tag: item.imageTag,
                       thumbnailPixels: thumbnailPixels,
                       fullPixels: fullPixels,
                       loader: services.images)
        cell.onSingleTap = { [weak self] in self?.toggleChrome() }
        return cell
    }
}

extension PhotoViewerViewController: UICollectionViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !isAdjustingLayout, laidOutSize.width > 0, scrollView === collectionView else { return }
        updateCurrentIndexPath()
    }
}

extension PhotoViewerViewController: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard detailsCard == nil, let cell = currentCell, !cell.isZoomed else { return false }
        let velocity = pan.velocity(in: view)
        return velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return true
    }
}

extension PhotoViewerViewController: ZoomTransitionEndpoint {

    func zoomTransitionImage() -> UIImage? {
        return currentCell?.imageView.image
    }

    func zoomTransitionRect(in container: UIView) -> CGRect? {
        guard let imageView = currentCell?.imageView, imageView.image != nil else { return nil }
        return imageView.convert(imageView.bounds, to: container)
    }

    func zoomTransitionSetHidden(_ hidden: Bool) {
        collectionView.isHidden = hidden
    }
}

extension PhotoViewerViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return ZoomTransition(presenting: true, source: transitionSource, destination: self)
    }

    func animationController(forDismissed dismissed: UIViewController)
        -> UIViewControllerAnimatedTransitioning? {
        onWillDismiss?(currentIndexPath)
        return ZoomTransition(presenting: false, source: self, destination: transitionSource)
    }
}

enum PhotoDateFormatter {

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        return formatter
    }()

    static func string(from date: Date?) -> String {
        guard let date = date else { return "Undated" }
        return formatter.string(from: date)
    }
}

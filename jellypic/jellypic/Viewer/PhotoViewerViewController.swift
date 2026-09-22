import UIKit

final class PhotoViewerViewController: UIViewController {

    private static let maximumFullPixels = 2048

    private let services: AppServices
    private let timeline: PhotoTimeline
    private let thumbnailPixels: Int
    private let fullPixels: Int

    private let backdrop = UIView()
    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let closeButton = FloatingButton(glyph: CloseGlyphView())
    private let moreButton = FloatingButton()
    private let playButton = FloatingButton(glyph: PlayGlyphView())
    private let datePill = SquircleView()
    private let dateLabel = UILabel()
    private let conversionPill = SquircleView()
    private let conversionLabel = UILabel()
    private var probeWork: DispatchWorkItem?
    private lazy var playback = VideoPlaybackController(services: services, presenter: self)

    private var isChromeVisible = false
    private var laidOutSize = CGSize.zero
    private var isAdjustingLayout = false
    private var detailsCard: PhotoDetailsViewController?
    private var currentPhotoId: String
    private var pendingTimelineChange = false

    private(set) var currentIndexPath: IndexPath

    weak var transitionSource: ZoomTransitionEndpoint?
    var onWillDismiss: ((IndexPath) -> Void)?
    var onShowLocation: ((Double, Double) -> Void)?

    init(services: AppServices,
         timeline: PhotoTimeline,
         startAt indexPath: IndexPath,
         thumbnailPixels: Int) {
        self.services = services
        self.timeline = timeline
        self.thumbnailPixels = thumbnailPixels
        self.currentIndexPath = indexPath
        self.currentPhotoId = timeline.photoIfPresent(at: indexPath)?.id ?? ""

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

    deinit {
        services.images.releaseFullSize()
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        updateForCurrentPhoto()
        setChrome(visible: false, animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let gap = ZoomablePhotoCell.gap
        collectionView.frame = view.bounds.insetBy(dx: -gap / 2, dy: 0)

        let size = collectionView.bounds.size
        guard size.width > 0, size != laidOutSize else { return }
        laidOutSize = size

        let wasAdjustingLayout = isAdjustingLayout
        isAdjustingLayout = true
        layout.itemSize = size
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: currentIndexPath,
                                    at: .centeredHorizontally,
                                    animated: false)
        isAdjustingLayout = wasAdjustingLayout
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

        playButton.isHidden = true
        playButton.addTarget(self, action: #selector(playVideo), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(playButton)

        conversionPill.cornerRadius = 15
        conversionPill.fillColor = Theme.palette.surface
        conversionPill.applyShadow(Theme.palette)
        conversionPill.isHidden = true
        conversionPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(conversionPill)

        conversionLabel.font = Typography.caption
        conversionLabel.adjustsFontForContentSizeCategory = true
        conversionLabel.textColor = Theme.palette.textPrimary
        conversionLabel.text = "Needs converting"
        conversionLabel.translatesAutoresizingMaskIntoConstraints = false
        conversionPill.addSubview(conversionLabel)

        playback.onBusyChanged = { [weak self] busy in
            self?.playButton.isUserInteractionEnabled = !busy
            self?.playButton.alpha = busy ? 0.5 : 1
        }

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 64),
            playButton.heightAnchor.constraint(equalToConstant: 64),

            conversionPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            conversionPill.topAnchor.constraint(equalTo: playButton.bottomAnchor, constant: 16),

            conversionLabel.leadingAnchor.constraint(equalTo: conversionPill.leadingAnchor, constant: 14),
            conversionLabel.trailingAnchor.constraint(equalTo: conversionPill.trailingAnchor, constant: -14),
            conversionLabel.topAnchor.constraint(equalTo: conversionPill.topAnchor, constant: 7),
            conversionLabel.bottomAnchor.constraint(equalTo: conversionPill.bottomAnchor, constant: -7),

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
        let point = CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY)
        guard let path = collectionView.indexPathForItem(at: point), path != currentIndexPath else {
            return
        }
        currentIndexPath = path
        updateForCurrentPhoto()
    }

    private func updateForCurrentPhoto() {
        guard let photo = timeline.photoIfPresent(at: currentIndexPath) else { return }
        currentPhotoId = photo.id
        dateLabel.text = PhotoDateFormatter.string(from: photo.captureDate)
        playButton.isHidden = !photo.isVideo
        conversionPill.isHidden = true
        scheduleProbe(for: photo)
    }

    private func scheduleProbe(for photo: Photo) {
        probeWork?.cancel()
        probeWork = nil
        guard photo.isVideo else { return }

        let itemId = photo.id
        let work = DispatchWorkItem { [weak self] in
            self?.playback.probe(itemId: itemId) { needsConversion in
                guard let self = self, self.currentPhotoId == itemId else { return }
                self.conversionPill.isHidden = !needsConversion
            }
        }
        probeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func setVideoOverlayAlpha(_ alpha: CGFloat) {
        playButton.alpha = alpha
        conversionPill.alpha = alpha
    }

    func timelineDidChange() {
        pendingTimelineChange = true
        applyTimelineChangeIfIdle()
    }

    private func applyTimelineChangeIfIdle() {
        guard pendingTimelineChange,
              isViewLoaded,
              !collectionView.isDragging,
              !collectionView.isDecelerating else { return }
        pendingTimelineChange = false

        guard let path = timeline.indexPath(forPhotoId: currentPhotoId) else {
            dismiss(animated: true, completion: nil)
            return
        }

        isAdjustingLayout = true
        currentIndexPath = path
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.scrollToItem(at: path, at: .centeredHorizontally, animated: false)
        isAdjustingLayout = false
        updateForCurrentPhoto()
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
              let photo = timeline.photoIfPresent(at: currentIndexPath) else { return }
        let card = PhotoDetailsViewController(services: services,
                                              itemId: photo.id,
                                              displayImage: currentCell?.imageView.image)
        card.onDismissed = { [weak self] in self?.detailsCard = nil }
        if let onShowLocation = onShowLocation {
            card.onShowLocation = onShowLocation
        }
        detailsCard = card
        card.present(over: self)
    }

    @objc private func playVideo() {
        guard let photo = timeline.photoIfPresent(at: currentIndexPath), photo.isVideo else { return }
        playback.play(itemId: photo.id)
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
            UIView.animate(withDuration: 0.2) { self.setVideoOverlayAlpha(0) }

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
                            self.setVideoOverlayAlpha(1)
                           },
                           completion: nil)

        default:
            break
        }
    }
}

extension PhotoViewerViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return timeline.sectionCount
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return timeline.numberOfPhotos(inSection: section)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZoomablePhotoCell.reuseIdentifier,
                                                      for: indexPath) as! ZoomablePhotoCell
        let photo = timeline.photo(at: indexPath)
        cell.configure(itemId: photo.id,
                       tag: photo.imageTag,
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

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            applyTimelineChangeIfIdle()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyTimelineChangeIfIdle()
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
        setVideoOverlayAlpha(hidden ? 0 : 1)
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

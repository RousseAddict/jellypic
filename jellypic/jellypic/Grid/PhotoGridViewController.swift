import UIKit

final class PhotoGridViewController: UIViewController {

    private static let chromeInset: CGFloat = 56
    private static let scrubberInset: CGFloat = 72
    private static let brandFadeDistance: CGFloat = 40
    private static let brandMarkSide: CGFloat = 22

    private let services: AppServices

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let settingsButton = GlyphButton(glyph: PersonGlyphView(), prominent: true)
    private let mapButton = GlyphButton(glyph: MapGlyphView(), prominent: true)
    private let banner = SyncBannerView()
    private let brand = UIStackView()
    private let brandLabel = UILabel()
    private let emptyLabel = UILabel()
    private let scrubber = MonthScrubberView()

    private var timeline: PhotoTimeline!
    private var pendingReload = false
    private var thumbnailPixels = 0
    private var horizontalInset: CGFloat = 0
    private var transitionIndexPath: IndexPath?
    private weak var hiddenCell: PhotoCell?
    private weak var viewer: PhotoViewerViewController?
    private var isBannerVisible = false
    private var isSessionExpired = false

    var onSignedOut: (() -> Void)?

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        buildTimeline()
        wireScrubber()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: Theme.didChangeNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionDidExpire),
                                               name: AppServices.sessionExpiredNotification,
                                               object: nil)

        applyPalette()
        refreshEmptyState()

        if services.isSessionExpired {
            sessionDidExpire()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startSync()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateItemSize()
    }

    private func buildHierarchy() {
        layout.minimumInteritemSpacing = GridMetrics.spacing
        layout.minimumLineSpacing = GridMetrics.spacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        collectionView.register(MonthHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonthHeaderView.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: PhotoGridViewController.chromeInset,
                                                   left: 0,
                                                   bottom: 0,
                                                   right: 0)
        view.addSubview(collectionView)

        emptyLabel.font = Typography.body
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No photos in this library yet."
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        let mark = UIImageView(image: UIImage(named: "LogoMark"))
        mark.contentMode = .scaleAspectFit
        mark.translatesAutoresizingMaskIntoConstraints = false

        brandLabel.font = Typography.headline
        brandLabel.adjustsFontForContentSizeCategory = true
        brandLabel.text = "Jellypic"

        brand.axis = .horizontal
        brand.alignment = .center
        brand.spacing = 8
        brand.isUserInteractionEnabled = false
        brand.translatesAutoresizingMaskIntoConstraints = false
        brand.addArrangedSubview(mark)
        brand.addArrangedSubview(brandLabel)
        view.addSubview(brand)

        banner.alpha = 0
        banner.onTap = { [weak self] in self?.presentReauth() }
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        scrubber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubber)

        settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(settingsButton)

        mapButton.addTarget(self, action: #selector(showMap), for: .touchUpInside)
        mapButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mapButton)

        NSLayoutConstraint.activate([
            scrubber.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                          constant: PhotoGridViewController.scrubberInset),
            scrubber.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                             constant: -16),
            scrubber.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrubber.widthAnchor.constraint(equalToConstant: MonthScrubberView.width),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            settingsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                     constant: -4),

            mapButton.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            mapButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor),

            mark.widthAnchor.constraint(equalToConstant: PhotoGridViewController.brandMarkSide),
            mark.heightAnchor.constraint(equalToConstant: PhotoGridViewController.brandMarkSide),

            brand.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            brand.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                           constant: 16),
            brand.trailingAnchor.constraint(lessThanOrEqualTo: mapButton.leadingAnchor,
                                            constant: -24),

            banner.centerYAnchor.constraint(equalTo: settingsButton.centerYAnchor),
            banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                            constant: 12),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: mapButton.leadingAnchor, constant: -24)
        ])
    }

    private func buildTimeline() {
        timeline = services.store.makeTimeline()
        timeline.onChange = { [weak self] in
            guard let self = self else { return }
            self.pendingReload = true
            self.applyReloadIfIdle()
            self.viewer?.timelineDidChange()
        }
        timeline.onReset = { [weak self] in
            guard let self = self else { return }
            self.pendingReload = false
            self.collectionView.reloadData()
            self.refreshEmptyState()
            self.viewer?.timelineDidChange()
        }
    }

    private func wireScrubber() {
        scrubber.onScrub = { [weak self] progress in
            self?.scrubTo(progress)
        }
        scrubber.onScrubbingChanged = { [weak self] isScrubbing in
            guard let self = self else { return }
            self.services.images.isSuspended = isScrubbing
            if !isScrubbing {
                self.reloadVisibleThumbnails()
            }
        }
    }

    private func scrubTo(_ progress: CGFloat) {
        guard let travel = scrollableHeight() else { return }
        let y = -collectionView.contentInset.top + travel * progress
        collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        scrubber.setTitle(topVisibleMonthTitle())
    }

    private func scrollableHeight() -> CGFloat? {
        let travel = collectionView.contentSize.height
            - collectionView.bounds.height
            + collectionView.contentInset.top
            + collectionView.contentInset.bottom
        return travel > 0 ? travel : nil
    }

    private func scrubberProgress() -> CGFloat {
        guard let travel = scrollableHeight() else { return 0 }
        let offset = collectionView.contentOffset.y + collectionView.contentInset.top
        return min(max(offset / travel, 0), 1)
    }

    private func topVisibleMonthTitle() -> String? {
        guard let section = collectionView.indexPathsForVisibleItems.map({ $0.section }).min() else {
            return nil
        }
        return MonthKey.shortTitle(for: timeline.monthKey(forSection: section))
    }

    private func reloadVisibleThumbnails() {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return }
        UIView.performWithoutAnimation {
            collectionView.reloadItems(at: visible)
        }
    }

    private func updateItemSize() {
        let inset = max(view.safeAreaInsets.left, view.safeAreaInsets.right)
        let width = collectionView.bounds.width - inset * 2
        guard width > 0 else { return }

        let side = GridMetrics.itemSide(forWidth: width)
        guard side > 0 else { return }

        let pixels = GridMetrics.thumbnailPixels(for: side)
        guard layout.itemSize.width != side || thumbnailPixels != pixels else { return }

        horizontalInset = inset
        layout.itemSize = CGSize(width: side, height: side)
        layout.sectionInset = UIEdgeInsets(top: 0, left: inset, bottom: 16, right: inset)
        layout.headerReferenceSize = CGSize(width: collectionView.bounds.width,
                                            height: MonthHeaderView.height)
        layout.invalidateLayout()

        guard thumbnailPixels != pixels else { return }
        thumbnailPixels = pixels
        collectionView.reloadData()
    }

    private func startSync() {
        guard let libraryId = Preferences.libraryId else { return }
        services.sync.onProgress = { [weak self] progress in
            self?.showBanner("Indexing \(progress.indexed) of \(progress.total)")
        }
        services.sync.onFinish = { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.showBanner(error.shortDescription)
            } else {
                self.hideBanner()
            }
            self.refreshEmptyState()
        }
        guard !services.sync.isRunning else { return }
        services.sync.start(libraryId: libraryId)
        if services.sync.isRunning {
            showBanner("Indexing…")
        }
    }

    private func showBanner(_ text: String) {
        guard !isSessionExpired else { return }
        banner.isBusy = true
        banner.text = text
        revealBanner()
    }

    private func revealBanner() {
        guard !isBannerVisible else { return }
        isBannerVisible = true
        UIView.animate(withDuration: 0.24) {
            self.banner.alpha = 1
            self.brand.alpha = self.brandAlpha()
        }
    }

    private func hideBanner() {
        guard isBannerVisible, !isSessionExpired else { return }
        isBannerVisible = false
        UIView.animate(withDuration: 0.24) {
            self.banner.alpha = 0
            self.brand.alpha = self.brandAlpha()
        }
    }

    private func headerAlpha() -> CGFloat {
        let scrolled = collectionView.contentOffset.y + collectionView.contentInset.top
        let progress = scrolled / PhotoGridViewController.brandFadeDistance
        return 1 - min(max(progress, 0), 1)
    }

    private func brandAlpha() -> CGFloat {
        return isBannerVisible ? 0 : headerAlpha()
    }

    private func updateHeaderAlpha() {
        let alpha = headerAlpha()
        brand.alpha = brandAlpha()
        settingsButton.alpha = alpha
        settingsButton.isUserInteractionEnabled = alpha > 0
        mapButton.alpha = alpha
        mapButton.isUserInteractionEnabled = alpha > 0
    }

    private func refreshEmptyState() {
        emptyLabel.isHidden = !timeline.isEmpty || services.sync.isRunning
    }

    private func applyReloadIfIdle() {
        guard pendingReload,
              !collectionView.isDragging,
              !collectionView.isDecelerating else { return }
        pendingReload = false
        collectionView.reloadData()
        refreshEmptyState()
    }

    @objc private func sessionDidExpire() {
        isSessionExpired = true
        banner.isBusy = false
        banner.text = "Session expired — tap to sign in"
        revealBanner()
    }

    private func presentReauth() {
        guard isSessionExpired, let session = services.authStore.session else { return }
        let reauth = ReauthViewController(services: services, session: session)
        reauth.onSignedIn = { [weak self] in self?.sessionDidResume() }
        reauth.present(over: self)
    }

    private func sessionDidResume() {
        isSessionExpired = false
        hideBanner()
        reloadVisibleThumbnails()
        startSync()
    }

    @objc private func showSettings() {
        let settings = SettingsViewController(services: services)
        settings.onSignedOut = { [weak self] in self?.onSignedOut?() }
        settings.onResyncRequested = { [weak self] in self?.restartSync() }
        settings.present(over: self)
    }

    @objc private func showMap() {
        presentMap(latitude: nil, longitude: nil)
    }

    private func presentMap(latitude: Double?, longitude: Double?) {
        let map = MapViewController(services: services)
        if let latitude = latitude, let longitude = longitude {
            map.focus(latitude: latitude, longitude: longitude)
        }
        present(map, animated: true, completion: nil)
    }

    private func restartSync() {
        guard let libraryId = Preferences.libraryId else { return }
        services.sync.refresh(libraryId: libraryId)
        if services.sync.isRunning {
            showBanner("Indexing…")
        }
    }

    @objc private func themeDidChange() {
        applyPalette()
        collectionView.reloadData()
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = palette.background
        collectionView.backgroundColor = palette.background
        emptyLabel.textColor = palette.textSecondary
        brandLabel.textColor = palette.textPrimary
        view.applyThemeRecursively(palette)
    }
}

extension PhotoGridViewController: UICollectionViewDataSource {

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

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                     withReuseIdentifier: MonthHeaderView.reuseIdentifier,
                                                                     for: indexPath) as! MonthHeaderView
        header.configure(monthKey: timeline.monthKey(forSection: indexPath.section),
                         palette: Theme.palette,
                         leadingInset: horizontalInset)
        return header
    }
}

extension PhotoGridViewController: UICollectionViewDelegate {

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
        viewer.onShowLocation = { [weak self] latitude, longitude in
            guard let self = self else { return }
            self.dismiss(animated: true) {
                self.presentMap(latitude: latitude, longitude: longitude)
            }
        }
        self.viewer = viewer
        present(viewer, animated: true, completion: nil)
    }

    private func prepareForReturn(to indexPath: IndexPath) {
        transitionIndexPath = indexPath
        guard collectionView.cellForItem(at: indexPath) == nil else { return }
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        collectionView.layoutIfNeeded()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateHeaderAlpha()
        scrubber.update(progress: scrubberProgress())
        scrubber.reveal()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            applyReloadIfIdle()
            scrubber.scheduleFade()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyReloadIfIdle()
        scrubber.scheduleFade()
    }
}

extension PhotoGridViewController: ZoomTransitionEndpoint {

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

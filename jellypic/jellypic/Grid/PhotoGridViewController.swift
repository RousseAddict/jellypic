import UIKit
import CoreData

final class PhotoGridViewController: UIViewController {

    private static let targetSide: CGFloat = 118
    private static let minimumColumns: CGFloat = 3
    private static let pixelStep = 64
    private static let spacing: CGFloat = 1
    private static let chromeInset: CGFloat = 56

    private let services: AppServices

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let moreButton = FloatingButton()
    private let banner = SyncBannerView()
    private let emptyLabel = UILabel()

    private var results: NSFetchedResultsController<PhotoItem>!
    private var pendingReload = false
    private var thumbnailPixels = 0
    private var horizontalInset: CGFloat = 0

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
        buildResults()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(themeDidChange),
                                               name: Theme.didChangeNotification,
                                               object: nil)

        applyPalette()
        refreshEmptyState()
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
        layout.minimumInteritemSpacing = PhotoGridViewController.spacing
        layout.minimumLineSpacing = PhotoGridViewController.spacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.alwaysBounceVertical = true
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
        collectionView.scrollIndicatorInsets = collectionView.contentInset
        view.addSubview(collectionView)

        emptyLabel.font = Typography.body
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.text = "No photos in this library yet."
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        banner.alpha = 0
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        moreButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        moreButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(moreButton)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            moreButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            moreButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                                 constant: -12),

            banner.centerYAnchor.constraint(equalTo: moreButton.centerYAnchor),
            banner.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                            constant: 12),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: moreButton.leadingAnchor, constant: -12)
        ])
    }

    private func buildResults() {
        let request = NSFetchRequest<PhotoItem>(entityName: PhotoItem.entityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: "monthKey", ascending: false),
            NSSortDescriptor(key: "captureDate", ascending: false),
            NSSortDescriptor(key: "id", ascending: false)
        ]
        request.fetchBatchSize = 60
        request.returnsObjectsAsFaults = false

        results = NSFetchedResultsController(fetchRequest: request,
                                             managedObjectContext: services.store.viewContext,
                                             sectionNameKeyPath: "monthKey",
                                             cacheName: nil)
        results.delegate = self
        try? results.performFetch()
    }

    private func updateItemSize() {
        let inset = max(view.safeAreaInsets.left, view.safeAreaInsets.right)
        let width = collectionView.bounds.width - inset * 2
        guard width > 0 else { return }

        let columns = max(PhotoGridViewController.minimumColumns,
                          (width / PhotoGridViewController.targetSide).rounded())
        let available = width - PhotoGridViewController.spacing * (columns - 1)
        let side = floor(available / columns)
        guard side > 0 else { return }

        let pixels = PhotoGridViewController.thumbnailPixels(for: side)
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

    private static func thumbnailPixels(for side: CGFloat) -> Int {
        let exact = Int((side * UIScreen.main.scale).rounded(.up))
        return (exact + pixelStep - 1) / pixelStep * pixelStep
    }

    private func startSync() {
        guard let libraryId = Preferences.libraryId else { return }
        services.sync.onProgress = { [weak self] progress in
            self?.showBanner("Indexing \(progress.indexed) of \(progress.total)")
        }
        services.sync.onFinish = { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.showBanner(error.localizedDescription)
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
        banner.text = text
        guard banner.alpha < 1 else { return }
        UIView.animate(withDuration: 0.24) { self.banner.alpha = 1 }
    }

    private func hideBanner() {
        guard banner.alpha > 0 else { return }
        UIView.animate(withDuration: 0.24) { self.banner.alpha = 0 }
    }

    private func refreshEmptyState() {
        let isEmpty = (results.fetchedObjects?.isEmpty ?? true)
        emptyLabel.isHidden = !isEmpty || services.sync.isRunning
    }

    private func applyReloadIfIdle() {
        guard pendingReload,
              !collectionView.isDragging,
              !collectionView.isDecelerating else { return }
        pendingReload = false
        collectionView.reloadData()
        refreshEmptyState()
    }

    @objc private func showSettings() {
        let settings = SettingsViewController(services: services)
        settings.onSignedOut = { [weak self] in self?.onSignedOut?() }
        settings.present(over: self)
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
        view.applyThemeRecursively(palette)
    }
}

extension PhotoGridViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return results.sections?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return results.sections?[section].numberOfObjects ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseIdentifier,
                                                      for: indexPath) as! PhotoCell
        let item = results.object(at: indexPath)
        cell.configure(itemId: item.id,
                       tag: item.imageTag,
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
        header.configure(monthKey: results.sections?[indexPath.section].name ?? "",
                         palette: Theme.palette,
                         leadingInset: horizontalInset)
        return header
    }
}

extension PhotoGridViewController: UICollectionViewDelegate {

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            applyReloadIfIdle()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        applyReloadIfIdle()
    }
}

extension PhotoGridViewController: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        pendingReload = true
        applyReloadIfIdle()
    }
}

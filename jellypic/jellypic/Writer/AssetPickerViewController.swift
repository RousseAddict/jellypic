import Photos
import UIKit

final class AssetPickerViewController: UIViewController {

    private struct MonthSection {
        let monthKey: String
        let first: Int
        var count: Int
    }

    private static let bandHeight: CGFloat = 56
    private static let scrubberInset: CGFloat = 72

    private let services: AppServices

    private let layout = UICollectionViewFlowLayout()
    private var collectionView: UICollectionView!
    private let cancelButton = BandTextButton()
    private let countLabel = UILabel()
    private let noticeLabel = UILabel()
    private let pill = SendPillButton()
    private let scrubber = MonthScrubberView()

    private let imageManager = PHCachingImageManager()
    private let requestOptions = PHImageRequestOptions()

    private var assets = PHFetchResult<PHAsset>()
    private var sections: [MonthSection] = []
    private var chosen = Set<String>()
    private var order: [String] = []

    private var thumbnailPixels = 0
    private var horizontalInset: CGFloat = 0
    private var isSending = false
    private var isPillVisible = false

    var onFinished: ((BackupSendSummary) -> Void)?

    init(services: AppServices) {
        self.services = services
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        imageManager.stopCachingImagesForAllAssets()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        applyPalette()
        requestAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateItemSize()
    }

    private func buildHierarchy() {
        requestOptions.deliveryMode = .opportunistic
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = false

        layout.minimumInteritemSpacing = GridMetrics.spacing
        layout.minimumLineSpacing = GridMetrics.spacing
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 96, right: 0)

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.prefetchDataSource = self
        collectionView.register(AssetGridCell.self,
                                forCellWithReuseIdentifier: AssetGridCell.reuseIdentifier)
        collectionView.register(MonthHeaderView.self,
                                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                                withReuseIdentifier: MonthHeaderView.reuseIdentifier)
        collectionView.contentInset = UIEdgeInsets(top: AssetPickerViewController.bandHeight,
                                                   left: 0,
                                                   bottom: 0,
                                                   right: 0)
        view.addSubview(collectionView)

        noticeLabel.font = Typography.body
        noticeLabel.adjustsFontForContentSizeCategory = true
        noticeLabel.textAlignment = .center
        noticeLabel.numberOfLines = 0
        noticeLabel.isHidden = true
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noticeLabel)

        scrubber.onScrub = { [weak self] progress in self?.scrubTo(progress) }
        scrubber.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrubber)

        cancelButton.title = "Cancel"
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)

        countLabel.font = Typography.headline
        countLabel.adjustsFontForContentSizeCategory = true
        countLabel.textAlignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)

        pill.alpha = 0
        pill.addTarget(self, action: #selector(send), for: .touchUpInside)
        pill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pill)

        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),

            countLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            countLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cancelButton.trailingAnchor,
                                                constant: 8),

            noticeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noticeLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            noticeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            noticeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            scrubber.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                          constant: AssetPickerViewController.scrubberInset),
            scrubber.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                             constant: -16),
            scrubber.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrubber.widthAnchor.constraint(equalToConstant: MonthScrubberView.width),

            pill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = palette.background
        collectionView.backgroundColor = palette.background
        noticeLabel.textColor = palette.textSecondary
        countLabel.textColor = palette.textPrimary
        view.applyThemeRecursively(palette)
    }

    // LEGACY(ios12): no .limited branch, PHAuthorizationStatus gains it at iOS 14. Freed at iOS 14.
    private func requestAccess() {
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard status == .authorized else {
                    self.showNotice(BackupUploadError.permissionDenied.text)
                    return
                }
                self.loadAssets()
            }
        }
    }

    private func loadAssets() {
        let collections = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                  subtype: .smartAlbumUserLibrary,
                                                                  options: nil)
        guard let library = collections.firstObject else {
            showNotice("No photos on this device.")
            return
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        assets = PHAsset.fetchAssets(in: library, options: options)

        var built: [MonthSection] = []
        assets.enumerateObjects { asset, index, _ in
            let key = AssetPickerViewController.monthKey(for: asset.creationDate)
            if let last = built.last, last.monthKey == key {
                built[built.count - 1].count += 1
            } else {
                built.append(MonthSection(monthKey: key, first: index, count: 1))
            }
        }
        sections = built

        guard !sections.isEmpty else {
            showNotice("No photos on this device.")
            return
        }
        collectionView.reloadData()
        updateCount()
        scrubber.reveal()
        scrubber.scheduleFade()
    }

    private func showNotice(_ text: String) {
        noticeLabel.text = text
        noticeLabel.isHidden = false
        collectionView.isHidden = true
        scrubber.isHidden = true
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
        layout.sectionInset = UIEdgeInsets(top: 0, left: inset, bottom: 96, right: inset)
        layout.headerReferenceSize = CGSize(width: collectionView.bounds.width,
                                            height: MonthHeaderView.height)
        layout.invalidateLayout()

        guard thumbnailPixels != pixels else { return }
        thumbnailPixels = pixels
        imageManager.stopCachingImagesForAllAssets()
        collectionView.reloadData()
    }

    private func asset(at indexPath: IndexPath) -> PHAsset {
        return assets.object(at: sections[indexPath.section].first + indexPath.item)
    }

    private func thumbnailSize() -> CGSize {
        return CGSize(width: thumbnailPixels, height: thumbnailPixels)
    }

    private func updateCount() {
        countLabel.text = order.isEmpty ? "Select photos" : "\(order.count) selected"
    }

    private func updatePill() {
        pill.title = "Send \(order.count)"
        setPillVisible(!order.isEmpty)
    }

    private func setPillVisible(_ visible: Bool) {
        guard visible != isPillVisible else { return }
        isPillVisible = visible
        if visible {
            pill.transform = CGAffineTransform(translationX: 0, y: 8)
        }
        UIView.animate(withDuration: 0.2,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.pill.alpha = visible ? 1 : 0
                        self.pill.transform = visible
                            ? .identity
                            : CGAffineTransform(translationX: 0, y: 8)
                       },
                       completion: nil)
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
        guard let section = collectionView.indexPathsForVisibleItems.map({ $0.section }).min(),
              section < sections.count else { return nil }
        return MonthKey.shortTitle(for: sections[section].monthKey)
    }

    @objc private func cancel() {
        guard !isSending else {
            services.upload.cancelSend()
            pill.title = "Stopping…"
            return
        }
        dismiss(animated: true, completion: nil)
    }

    @objc private func send() {
        guard !isSending, !order.isEmpty else { return }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: order, options: nil)
        var selected: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in selected.append(asset) }
        guard !selected.isEmpty else { return }

        isSending = true
        collectionView.isUserInteractionEnabled = false
        cancelButton.title = "Stop"
        pill.isEnabled = false

        let total = selected.count
        services.upload.send(selected, progress: { [weak self] done in
            self?.pill.title = "Sending \(done + 1) of \(total)"
        }, completion: { [weak self] summary in
            guard let self = self else { return }
            self.isSending = false
            let onFinished = self.onFinished
            self.dismiss(animated: true) { onFinished?(summary) }
        })
    }
}

extension AssetPickerViewController: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return sections.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        return sections[section].count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: AssetGridCell.reuseIdentifier,
                                                      for: indexPath) as! AssetGridCell
        let asset = self.asset(at: indexPath)
        cell.configure(asset: asset,
                       pixels: thumbnailPixels,
                       chosen: chosen.contains(asset.localIdentifier),
                       palette: Theme.palette,
                       manager: imageManager,
                       options: requestOptions)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView,
                        viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind,
                                                                     withReuseIdentifier: MonthHeaderView.reuseIdentifier,
                                                                     for: indexPath) as! MonthHeaderView
        header.configure(monthKey: sections[indexPath.section].monthKey,
                         palette: Theme.palette,
                         leadingInset: horizontalInset)
        return header
    }
}

extension AssetPickerViewController: UICollectionViewDataSourcePrefetching {

    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard thumbnailPixels > 0 else { return }
        imageManager.startCachingImages(for: indexPaths.map { asset(at: $0) },
                                        targetSize: thumbnailSize(),
                                        contentMode: .aspectFill,
                                        options: requestOptions)
    }

    func collectionView(_ collectionView: UICollectionView,
                        cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard thumbnailPixels > 0 else { return }
        imageManager.stopCachingImages(for: indexPaths.map { asset(at: $0) },
                                       targetSize: thumbnailSize(),
                                       contentMode: .aspectFill,
                                       options: requestOptions)
    }
}

extension AssetPickerViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard !isSending else { return }

        let identifier = asset(at: indexPath).localIdentifier
        if chosen.remove(identifier) != nil {
            order.removeAll { $0 == identifier }
        } else {
            chosen.insert(identifier)
            order.append(identifier)
        }

        let cell = collectionView.cellForItem(at: indexPath) as? AssetGridCell
        cell?.setChosen(chosen.contains(identifier), animated: true)
        updateCount()
        updatePill()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        scrubber.update(progress: scrubberProgress())
        scrubber.reveal()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            scrubber.scheduleFade()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrubber.scheduleFade()
    }
}

extension AssetPickerViewController {

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static func monthKey(for date: Date?) -> String {
        guard let date = date else { return "" }
        return monthFormatter.string(from: date)
    }
}

private final class BandTextButton: UIControl, Themed {

    private let label = UILabel()

    var title: String = "" {
        didSet { label.text = title }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        label.font = Typography.button
        label.adjustsFontForContentSizeCategory = true
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.5 : 1 }
    }

    func applyTheme(_ palette: ThemePalette) {
        label.textColor = palette.textPrimary
    }
}

private final class SendPillButton: UIControl, Themed {

    private let surface = SquircleView()
    private let label = UILabel()
    private var palette = Theme.palette

    var title: String = "" {
        didSet { label.text = title }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        label.font = Typography.button
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.isUserInteractionEnabled = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24)
        ])

        applyTheme(palette)
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
                self.label.alpha = self.isHighlighted ? 0.6 : 1
            }
        }
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        surface.fillColor = palette.accent
        surface.applyShadow(palette)
        label.textColor = palette.onAccent
    }
}

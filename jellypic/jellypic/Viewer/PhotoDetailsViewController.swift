import UIKit

final class PhotoDetailsViewController: UIViewController {

    private let services: AppServices
    private let itemId: String
    private let displayImage: UIImage?

    private let dimming = UIView()
    private let card = SquircleView()
    private let titleLabel = UILabel()
    private let scrollView = UIScrollView()
    private let rows = UIStackView()
    private let shareButton = ActionButton()

    private var details: PhotoDetailsDTO?
    private var originalBytes: Int64?
    private var downloadTask: URLSessionTask?

    var onDismissed: (() -> Void)?

    init(services: AppServices, itemId: String, displayImage: UIImage?) {
        self.services = services
        self.itemId = itemId
        self.displayImage = displayImage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        downloadTask?.cancel()
    }

    func present(over parent: UIViewController) {
        parent.addChild(self)
        view.frame = parent.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.view.addSubview(view)
        didMove(toParent: parent)

        view.layoutIfNeeded()
        card.transform = CGAffineTransform(translationX: 0, y: card.bounds.height)
        UIView.animate(withDuration: 0.34,
                       delay: 0,
                       usingSpringWithDamping: 0.9,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.dimming.alpha = 1
                        self.card.transform = .identity
                       },
                       completion: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        applyPalette()
        render()
        fetch()
    }

    private func buildHierarchy() {
        dimming.alpha = 0
        dimming.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dimming)

        card.cornerRadius = 32
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = "Details"
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(scrollView)

        rows.axis = .vertical
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(rows)

        shareButton.title = "Share"
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(shareButton)

        let maximumHeight = scrollView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor,
                                                               multiplier: 0.5)
        maximumHeight.priority = .required

        let contentHeight = scrollView.heightAnchor.constraint(equalTo: rows.heightAnchor)
        contentHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 32),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            maximumHeight,
            contentHeight,

            rows.topAnchor.constraint(equalTo: scrollView.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            rows.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            shareButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 24),
            shareButton.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            shareButton.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            shareButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                                constant: -24)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissCard))
        dimming.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissCard))
        swipe.direction = .down
        card.addGestureRecognizer(swipe)
    }

    private func fetch() {
        services.client.photoDetails(itemId: itemId) { [weak self] result in
            guard let self = self else { return }
            guard case .success(let details) = result else { return }
            self.details = details
            self.render()
        }
        services.client.originalFileSize(itemId: itemId) { [weak self] bytes in
            guard let self = self, let bytes = bytes else { return }
            self.originalBytes = bytes
            self.render()
        }
    }

    private func render() {
        for row in rows.arrangedSubviews {
            row.removeFromSuperview()
        }

        guard let details = details else {
            addRow("", "Loading…")
            return
        }

        addRow("File", details.fileName)
        addRow("Date", PhotoDetailsFormatter.timestamp(details.captureDate))
        addRow("Dimensions", PhotoDetailsFormatter.dimensions(details.width, details.height))
        addRow("Size", PhotoDetailsFormatter.bytes(originalBytes))
        addRow("Format", details.container?.uppercased())
        addRow("Camera", PhotoDetailsFormatter.camera(make: details.cameraMake,
                                                      model: details.cameraModel))
        addRow("Focal length", PhotoDetailsFormatter.focalLength(details.focalLength))
        addRow("Exposure", PhotoDetailsFormatter.exposure(fNumber: details.fNumber,
                                                          seconds: details.exposureSeconds,
                                                          iso: details.isoSpeedRating))
        addRow("Software", details.software)
        addRow("Location", PhotoDetailsFormatter.coordinates(latitude: details.latitude,
                                                             longitude: details.longitude))
        addRow("Altitude", PhotoDetailsFormatter.altitude(details.altitude))
    }

    private func addRow(_ key: String, _ value: String?) {
        guard let value = value, !value.isEmpty else { return }
        let palette = Theme.palette

        let keyLabel = UILabel()
        keyLabel.font = Typography.caption
        keyLabel.adjustsFontForContentSizeCategory = true
        keyLabel.textColor = palette.textSecondary
        keyLabel.text = key
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)
        keyLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let valueLabel = UILabel()
        valueLabel.font = Typography.caption
        valueLabel.adjustsFontForContentSizeCategory = true
        valueLabel.textColor = palette.textPrimary
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.text = value

        let row = UIStackView(arrangedSubviews: [keyLabel, valueLabel])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 16
        rows.addArrangedSubview(row)
    }

    @objc private func share() {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        if let image = displayImage {
            let title = "Optimised photo · \(Int(image.size.width * image.scale)) px"
            sheet.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                self?.presentActivity(with: [image], from: nil)
            })
        }

        var originalTitle = "Original file"
        if let bytes = originalBytes, let size = PhotoDetailsFormatter.bytes(bytes) {
            originalTitle += " · \(size)"
        }
        sheet.addAction(UIAlertAction(title: originalTitle, style: .default) { [weak self] _ in
            self?.shareOriginal()
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))

        sheet.popoverPresentationController?.sourceView = shareButton
        sheet.popoverPresentationController?.sourceRect = shareButton.bounds
        present(sheet, animated: true, completion: nil)
    }

    private func shareOriginal() {
        shareButton.isLoading = true
        let fileName = details?.fileName ?? "\(itemId).jpg"
        downloadTask = services.client.downloadOriginal(itemId: itemId,
                                                        fileName: fileName) { [weak self] result in
            guard let self = self else { return }
            self.shareButton.isLoading = false
            self.downloadTask = nil
            switch result {
            case .success(let url):
                self.presentActivity(with: [url], from: url)
            case .failure(let error):
                self.presentFailure(error)
            }
        }
    }

    private func presentActivity(with items: [Any], from fileURL: URL?) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = shareButton
        activity.popoverPresentationController?.sourceRect = shareButton.bounds
        activity.completionWithItemsHandler = { _, _, _, _ in
            guard let fileURL = fileURL else { return }
            try? FileManager.default.removeItem(at: fileURL)
        }
        present(activity, animated: true, completion: nil)
    }

    private func presentFailure(_ error: JellyfinError) {
        let alert = UIAlertController(title: "Could not download",
                                      message: error.localizedDescription,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    @objc private func dismissCard() {
        UIView.animate(withDuration: 0.26,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.dimming.alpha = 0
                        self.card.transform = CGAffineTransform(translationX: 0,
                                                                y: self.card.bounds.height)
                       },
                       completion: { _ in
                        self.willMove(toParent: nil)
                        self.view.removeFromSuperview()
                        self.removeFromParent()
                        self.onDismissed?()
                       })
    }

    private func applyPalette() {
        let palette = Theme.palette
        view.backgroundColor = .clear
        dimming.backgroundColor = UIColor(white: 0, alpha: 0.4)
        card.fillColor = palette.surface
        card.applyShadow(palette)
        titleLabel.textColor = palette.textPrimary
        view.applyThemeRecursively(palette)
    }
}

enum PhotoDetailsFormatter {

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    static func timestamp(_ date: Date?) -> String? {
        guard let date = date else { return nil }
        return timestampFormatter.string(from: date)
    }

    static func bytes(_ bytes: Int64?) -> String? {
        guard let bytes = bytes, bytes > 0 else { return nil }
        return byteFormatter.string(fromByteCount: bytes)
    }

    static func dimensions(_ width: Int?, _ height: Int?) -> String? {
        guard let width = width, let height = height, width > 0, height > 0 else { return nil }
        let megapixels = Double(width * height) / 1_000_000
        return String(format: "%d × %d · %.1f MP", width, height, megapixels)
    }

    static func camera(make: String?, model: String?) -> String? {
        let make = trimmed(make)
        let model = trimmed(model)
        guard let model = model else { return make }
        guard let make = make else { return model }
        if model.lowercased().hasPrefix(make.lowercased()) {
            return model
        }
        return "\(make) \(model)"
    }

    static func focalLength(_ millimetres: Double?) -> String? {
        guard let millimetres = millimetres, millimetres > 0 else { return nil }
        return String(format: "%.0f mm", millimetres)
    }

    static func exposure(fNumber: Double?, seconds: Double?, iso: Int?) -> String? {
        var parts: [String] = []
        if let fNumber = fNumber {
            parts.append(String(format: "ƒ/%.1f", fNumber))
        }
        if let seconds = seconds, seconds > 0 {
            parts.append(seconds >= 1
                ? String(format: "%.1f s", seconds)
                : "1/\(Int((1 / seconds).rounded())) s")
        }
        if let iso = iso, iso > 0 {
            parts.append("ISO \(iso)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func coordinates(latitude: Double?, longitude: Double?) -> String? {
        guard let latitude = latitude, let longitude = longitude else { return nil }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }

    static func altitude(_ metres: Double?) -> String? {
        guard let metres = metres else { return nil }
        return String(format: "%.0f m", metres)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

import UIKit

final class PhotoDetailsViewController: CardSheetViewController {

    private let services: AppServices
    private let itemId: String
    private let displayImage: UIImage?

    private let titleLabel = UILabel()
    private let progressLabel = UILabel()
    private let progressTrack = SquircleView()
    private let progressFill = SquircleView()
    private let shareButton = GlyphButton(glyph: ShareGlyphView())
    private let cancelButton = GlyphButton(glyph: StopGlyphView())

    private var progressWidth: NSLayoutConstraint!
    private var details: PhotoDetailsDTO?
    private var detailsError: JellyfinError?
    private var originalBytes: Int64?
    private var downloadTask: URLSessionTask?

    var onShowLocation: ((Double, Double) -> Void)?

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

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        applyPalette()
        render()
        fetch()
    }

    private func buildHierarchy() {
        titleLabel.font = Typography.title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = "Details"
        setHeaderView(titleLabel)

        body.spacing = 10

        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelDownload), for: .touchUpInside)
        cancelButton.isHidden = true
        addAccessory(shareButton)
        addAccessory(cancelButton)

        progressLabel.font = Typography.caption
        progressLabel.adjustsFontForContentSizeCategory = true

        progressTrack.cornerRadius = 2

        progressFill.cornerRadius = 2
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.addSubview(progressFill)

        progressWidth = progressFill.widthAnchor.constraint(equalToConstant: 0)

        footer.spacing = 8
        footer.addArrangedSubview(progressLabel)
        footer.addArrangedSubview(progressTrack)

        NSLayoutConstraint.activate([
            progressTrack.heightAnchor.constraint(equalToConstant: 4),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressWidth
        ])
    }

    private func fetch() {
        services.client.photoDetails(itemId: itemId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let details):
                self.details = details
            case .failure(let error):
                self.detailsError = error
            }
            self.render()
        }
        services.client.originalFileSize(itemId: itemId) { [weak self] bytes in
            guard let self = self, let bytes = bytes else { return }
            self.originalBytes = bytes
            self.render()
        }
    }

    private func render() {
        for row in body.arrangedSubviews {
            row.removeFromSuperview()
        }

        guard let details = details else {
            addRow("", detailsError?.shortDescription ?? "Loading…")
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
        addRow("Location",
               PhotoDetailsFormatter.coordinates(latitude: details.latitude,
                                                 longitude: details.longitude),
               action: onShowLocation == nil ? nil : #selector(showLocation))
        addRow("Altitude", PhotoDetailsFormatter.altitude(details.altitude))
    }

    @objc private func showLocation() {
        guard let latitude = details?.latitude, let longitude = details?.longitude else { return }
        dismissCard()
        onShowLocation?(latitude, longitude)
    }

    private func addRow(_ key: String, _ value: String?, action: Selector? = nil) {
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
        valueLabel.textColor = action == nil ? palette.textPrimary : palette.accent
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.text = value

        let row = UIStackView(arrangedSubviews: [keyLabel, valueBox(valueLabel, action: action)])
        row.axis = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 16
        body.addArrangedSubview(row)

        guard let action = action else { return }
        row.isUserInteractionEnabled = true
        row.addGestureRecognizer(UITapGestureRecognizer(target: self, action: action))
    }

    private func valueBox(_ valueLabel: UILabel, action: Selector?) -> UIView {
        guard action != nil else { return valueLabel }

        let chevron = ChevronGlyphView()
        chevron.color = Theme.palette.accent
        chevron.translatesAutoresizingMaskIntoConstraints = false

        let box = UIStackView(arrangedSubviews: [valueLabel, chevron])
        box.axis = .horizontal
        box.alignment = .center
        box.spacing = 6

        NSLayoutConstraint.activate([
            chevron.widthAnchor.constraint(equalToConstant: chevron.glyphSize.width),
            chevron.heightAnchor.constraint(equalToConstant: chevron.glyphSize.height)
        ])
        return box
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
        let fileName = details?.fileName ?? "\(itemId).jpg"
        setDownloading(true)
        showProgress(received: 0, expected: originalBytes ?? 0)

        downloadTask = services.client.downloadOriginal(
            itemId: itemId,
            fileName: fileName,
            progress: { [weak self] received, expected in
                self?.showProgress(received: received, expected: expected)
            },
            completion: { [weak self] result in
                guard let self = self else { return }
                self.setDownloading(false)
                switch result {
                case .success(let url):
                    self.presentActivity(with: [url], from: url)
                case .failure(let error):
                    self.presentFailure(error)
                }
            })
    }

    @objc private func cancelDownload() {
        downloadTask?.cancel()
        setDownloading(false)
    }

    private func setDownloading(_ downloading: Bool) {
        if !downloading {
            downloadTask = nil
        }
        shareButton.isHidden = downloading
        cancelButton.isHidden = !downloading
        guard footer.isHidden == downloading else { return }
        UIView.animate(withDuration: 0.24,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.footer.isHidden = !downloading
                        self.view.layoutIfNeeded()
                       },
                       completion: nil)
    }

    private func showProgress(received: Int64, expected: Int64) {
        guard expected > 0 else {
            progressLabel.text = PhotoDetailsFormatter.bytes(received)
            return
        }
        progressLabel.text = "\(PhotoDetailsFormatter.bytes(received) ?? "0 bytes") of \(PhotoDetailsFormatter.bytes(expected) ?? "?")"
        progressTrack.layoutIfNeeded()
        let fraction = min(max(Double(received) / Double(expected), 0), 1)
        progressWidth.constant = progressTrack.bounds.width * CGFloat(fraction)
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

    private func applyPalette() {
        let palette = Theme.palette
        applySheetPalette(palette)
        titleLabel.textColor = palette.textPrimary
        progressLabel.textColor = palette.textSecondary
        progressTrack.fillColor = palette.field
        progressFill.fillColor = palette.accent
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

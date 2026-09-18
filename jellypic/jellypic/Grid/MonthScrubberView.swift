import UIKit

final class MonthScrubberView: UIView, Themed {

    static let width: CGFloat = 40

    private static let thumbWidth: CGFloat = 20
    private static let thumbHeight: CGFloat = 44
    private static let grabInset: CGFloat = 14
    private static let idleDelay: TimeInterval = 1.5

    private let thumb = SquircleView()
    private let grip = HandleGlyphView()
    private let bubble = SquircleView()
    private let bubbleLabel = UILabel()

    private var thumbCenterY: NSLayoutConstraint!
    private var idleTimer: Timer?
    private var progress: CGFloat = 0

    private(set) var isScrubbing = false

    var onScrub: ((CGFloat) -> Void)?
    var onScrubbingChanged: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        alpha = 0

        thumb.cornerRadius = MonthScrubberView.thumbWidth / 2
        thumb.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumb)

        grip.isUserInteractionEnabled = false
        grip.translatesAutoresizingMaskIntoConstraints = false
        thumb.addSubview(grip)

        bubble.cornerRadius = 16
        bubble.alpha = 0
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        bubbleLabel.font = Typography.headline
        bubbleLabel.adjustsFontForContentSizeCategory = true
        bubbleLabel.textAlignment = .center
        bubbleLabel.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(bubbleLabel)

        thumbCenterY = thumb.centerYAnchor.constraint(equalTo: topAnchor)

        NSLayoutConstraint.activate([
            thumb.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            thumb.widthAnchor.constraint(equalToConstant: MonthScrubberView.thumbWidth),
            thumb.heightAnchor.constraint(equalToConstant: MonthScrubberView.thumbHeight),
            thumbCenterY,

            grip.centerXAnchor.constraint(equalTo: thumb.centerXAnchor),
            grip.centerYAnchor.constraint(equalTo: thumb.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: grip.glyphSize.width),
            grip.heightAnchor.constraint(equalToConstant: grip.glyphSize.height),

            bubble.trailingAnchor.constraint(equalTo: thumb.leadingAnchor, constant: -10),
            bubble.centerYAnchor.constraint(equalTo: thumb.centerYAnchor),

            bubbleLabel.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
            bubbleLabel.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
            bubbleLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 14),
            bubbleLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -14)
        ])

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        idleTimer?.invalidate()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard alpha > 0.01 else { return false }
        let inset = MonthScrubberView.grabInset
        return thumb.frame.insetBy(dx: -inset, dy: -inset).contains(point)
    }

    func update(progress: CGFloat) {
        guard !isScrubbing else { return }
        self.progress = min(max(progress, 0), 1)
        positionThumb()
    }

    func setTitle(_ title: String?) {
        bubbleLabel.text = title
    }

    func reveal() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard alpha < 1 else { return }
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
    }

    func scheduleFade() {
        guard !isScrubbing else { return }
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(timeInterval: MonthScrubberView.idleDelay,
                                         target: self,
                                         selector: #selector(fade),
                                         userInfo: nil,
                                         repeats: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionThumb()
    }

    private func positionThumb() {
        let travel = bounds.height - MonthScrubberView.thumbHeight
        guard travel > 0 else { return }
        thumbCenterY.constant = MonthScrubberView.thumbHeight / 2 + travel * progress
    }

    @objc private func fade() {
        idleTimer = nil
        UIView.animate(withDuration: 0.3) { self.alpha = 0 }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let travel = bounds.height - MonthScrubberView.thumbHeight
        guard travel > 0 else { return }

        switch recognizer.state {
        case .began:
            isScrubbing = true
            idleTimer?.invalidate()
            onScrubbingChanged?(true)
            UIView.animate(withDuration: 0.16) {
                self.alpha = 1
                self.bubble.alpha = 1
                self.thumb.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }
        case .changed:
            let location = recognizer.location(in: self).y - MonthScrubberView.thumbHeight / 2
            progress = min(max(location / travel, 0), 1)
            positionThumb()
            onScrub?(progress)
        case .ended, .cancelled, .failed:
            isScrubbing = false
            onScrubbingChanged?(false)
            UIView.animate(withDuration: 0.2,
                           animations: {
                            self.bubble.alpha = 0
                            self.thumb.transform = .identity
                           },
                           completion: { _ in
                            self.scheduleFade()
                           })
        default:
            break
        }
    }

    func applyTheme(_ palette: ThemePalette) {
        thumb.fillColor = palette.surface
        thumb.applyShadow(palette)
        grip.color = palette.textSecondary
        bubble.fillColor = palette.accent
        bubble.applyShadow(palette)
        bubbleLabel.textColor = palette.onAccent
    }
}

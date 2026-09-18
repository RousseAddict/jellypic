import UIKit

class CardSheetViewController: UIViewController {

    let card = SquircleView()
    let body = UIStackView()
    let footer = UIStackView()
    let closeButton = CardAccessoryButton(glyph: CloseGlyphView())

    var onDismissed: (() -> Void)?

    private static let overhang: CGFloat = 32
    private static let padding: CGFloat = 24
    private static let topGap: CGFloat = 64

    private let dimming = UIView()
    private let sheet = UIStackView()
    private let header = UIStackView()
    private let accessories = UIStackView()
    private let scrollView = UIScrollView()

    private var bottomSheetConstraints: [NSLayoutConstraint] = []
    private var fullSheetConstraints: [NSLayoutConstraint] = []
    private var isFullSheet: Bool?

    override func viewDidLoad() {
        super.viewDidLoad()
        buildDimming()
        buildCard()
        buildSheet()
        buildModeConstraints()
        updateSheetMode()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateSheetMode()
    }

    func setHeaderView(_ view: UIView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        header.insertArrangedSubview(view, at: 0)
    }

    func addAccessory(_ button: CardAccessoryButton) {
        accessories.insertArrangedSubview(button, at: 0)
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

    @objc func dismissCard() {
        UIView.animate(withDuration: 0.26,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: {
                        self.dimming.alpha = 0
                        self.card.transform = CGAffineTransform(translationX: 0,
                                                                y: self.card.bounds.height)
                       },
                       completion: { _ in
                        self.detachFromParent()
                        self.onDismissed?()
                       })
    }

    func detachFromParent() {
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }

    func applySheetPalette(_ palette: ThemePalette) {
        view.backgroundColor = .clear
        dimming.backgroundColor = UIColor(white: 0, alpha: 0.4)
        card.fillColor = palette.surface
        card.applyShadow(palette)
    }

    private func buildDimming() {
        dimming.alpha = 0
        dimming.translatesAutoresizingMaskIntoConstraints = false
        dimming.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                            action: #selector(dismissCard)))
        view.addSubview(dimming)

        NSLayoutConstraint.activate([
            dimming.topAnchor.constraint(equalTo: view.topAnchor),
            dimming.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dimming.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dimming.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func buildCard() {
        card.cornerRadius = 32
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(dismissCard))
        swipe.direction = .down
        card.addGestureRecognizer(swipe)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor,
                                         constant: CardSheetViewController.overhang)
        ])
    }

    private func buildSheet() {
        closeButton.addTarget(self, action: #selector(dismissCard), for: .touchUpInside)

        accessories.axis = .horizontal
        accessories.spacing = 4
        accessories.alignment = .top
        accessories.setContentHuggingPriority(.required, for: .horizontal)
        accessories.setContentCompressionResistancePriority(.required, for: .horizontal)
        accessories.addArrangedSubview(closeButton)

        header.axis = .horizontal
        header.spacing = 12
        header.alignment = .top
        header.addArrangedSubview(accessories)

        body.axis = .vertical
        body.spacing = 18
        body.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(body)

        scrollView.alwaysBounceVertical = false

        footer.axis = .vertical
        footer.spacing = 16
        footer.isHidden = true

        sheet.axis = .vertical
        sheet.spacing = 22
        sheet.translatesAutoresizingMaskIntoConstraints = false
        sheet.addArrangedSubview(header)
        sheet.addArrangedSubview(scrollView)
        sheet.addArrangedSubview(footer)
        card.addSubview(sheet)

        let fit = scrollView.heightAnchor.constraint(equalTo: body.heightAnchor)
        fit.priority = UILayoutPriority(500)

        NSLayoutConstraint.activate([
            body.topAnchor.constraint(equalTo: scrollView.topAnchor),
            body.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            body.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            body.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            fit,

            sheet.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                          constant: -CardSheetViewController.padding)
        ])
    }

    private func buildModeConstraints() {
        let overhang = CardSheetViewController.overhang
        let padding = CardSheetViewController.padding

        bottomSheetConstraints = [
            card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor,
                                      constant: CardSheetViewController.topGap),
            sheet.topAnchor.constraint(equalTo: card.topAnchor, constant: padding),
            sheet.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: padding),
            sheet.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -padding)
        ]

        fullSheetConstraints = [
            card.topAnchor.constraint(equalTo: view.topAnchor, constant: -overhang),
            sheet.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                       constant: padding),
            sheet.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor,
                                           constant: padding),
            sheet.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor,
                                            constant: -padding)
        ]
    }

    private func updateSheetMode() {
        guard isViewLoaded else { return }
        let fullSheet = traitCollection.verticalSizeClass == .compact
        guard fullSheet != isFullSheet else { return }
        isFullSheet = fullSheet

        NSLayoutConstraint.deactivate(fullSheet ? bottomSheetConstraints : fullSheetConstraints)
        NSLayoutConstraint.activate(fullSheet ? fullSheetConstraints : bottomSheetConstraints)
    }
}

final class CardAccessoryButton: UIControl, Themed {

    static let side: CGFloat = 44

    private let glyph: GlyphView

    init(glyph: GlyphView) {
        self.glyph = glyph
        super.init(frame: .zero)
        backgroundColor = .clear

        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: CardAccessoryButton.side),
            heightAnchor.constraint(equalToConstant: CardAccessoryButton.side),

            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: glyph.glyphSize.width),
            glyph.heightAnchor.constraint(equalToConstant: glyph.glyphSize.height)
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
        glyph.color = palette.textSecondary
    }
}

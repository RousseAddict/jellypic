import UIKit

final class MoreGlyphView: UIView {

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    var color: UIColor = .black {
        didSet { shapeLayer.fillColor = color.cgColor }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shapeLayer.fillColor = color.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 18, height: 4)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let diameter = min(bounds.height, bounds.width / 4)
        guard diameter > 0 else { return }

        let spacing = (bounds.width - diameter * 3) / 2
        let path = UIBezierPath()
        for index in 0..<3 {
            let origin = CGPoint(x: CGFloat(index) * (diameter + spacing),
                                 y: (bounds.height - diameter) / 2)
            path.append(UIBezierPath(ovalIn: CGRect(origin: origin,
                                                    size: CGSize(width: diameter, height: diameter))))
        }
        shapeLayer.path = path.cgPath
    }
}

final class FloatingButton: UIControl, Themed {

    private let surface = SquircleView()
    private let glyph = MoreGlyphView()
    private var palette = Theme.palette

    override init(frame: CGRect) {
        super.init(frame: frame)

        surface.isUserInteractionEnabled = false
        surface.translatesAutoresizingMaskIntoConstraints = false
        addSubview(surface)

        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),

            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            glyph.heightAnchor.constraint(equalToConstant: 4)
        ])

        applyTheme(palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 44, height: 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        surface.cornerRadius = bounds.height / 2
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.94, y: 0.94)
                    : .identity
            }
        }
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        surface.fillColor = palette.surface
        surface.applyShadow(palette)
        glyph.color = palette.textPrimary
    }
}

import UIKit

class GlyphView: UIView {

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    var color: UIColor = .black {
        didSet { applyColor() }
    }

    var glyphSize: CGSize {
        return CGSize(width: 18, height: 18)
    }

    var strokeWidth: CGFloat {
        return 0
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shapeLayer.lineCap = .round
        shapeLayer.lineWidth = strokeWidth
        applyColor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return glyphSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.path = path(in: bounds).cgPath
    }

    func path(in rect: CGRect) -> UIBezierPath {
        return UIBezierPath()
    }

    private func applyColor() {
        let stroked = strokeWidth > 0
        shapeLayer.fillColor = stroked ? UIColor.clear.cgColor : color.cgColor
        shapeLayer.strokeColor = stroked ? color.cgColor : UIColor.clear.cgColor
    }
}

final class MoreGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 18, height: 4)
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        let diameter = min(rect.height, rect.width / 4)
        guard diameter > 0 else { return UIBezierPath() }

        let spacing = (rect.width - diameter * 3) / 2
        let path = UIBezierPath()
        for index in 0..<3 {
            let origin = CGPoint(x: CGFloat(index) * (diameter + spacing),
                                 y: (rect.height - diameter) / 2)
            path.append(UIBezierPath(ovalIn: CGRect(origin: origin,
                                                    size: CGSize(width: diameter, height: diameter))))
        }
        return path
    }
}

final class HandleGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 4, height: 18)
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        let diameter = min(rect.width, rect.height / 4)
        guard diameter > 0 else { return UIBezierPath() }

        let spacing = (rect.height - diameter * 3) / 2
        let path = UIBezierPath()
        for index in 0..<3 {
            let origin = CGPoint(x: (rect.width - diameter) / 2,
                                 y: CGFloat(index) * (diameter + spacing))
            path.append(UIBezierPath(ovalIn: CGRect(origin: origin,
                                                    size: CGSize(width: diameter, height: diameter))))
        }
        return path
    }
}

final class CloseGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 15, height: 15)
    }

    override var strokeWidth: CGFloat {
        return 2
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        let box = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.move(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        return path
    }
}

final class FloatingButton: UIControl, Themed {

    private let surface = SquircleView()
    private let glyph: GlyphView
    private var palette = Theme.palette

    init(glyph: GlyphView = MoreGlyphView()) {
        self.glyph = glyph
        super.init(frame: .zero)

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
            glyph.widthAnchor.constraint(equalToConstant: glyph.glyphSize.width),
            glyph.heightAnchor.constraint(equalToConstant: glyph.glyphSize.height)
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

import UIKit

// LEGACY(ios12): every GlyphView subclass below is a hand-drawn CAShapeLayer because SF Symbols are iOS 13+. Freed at iOS 13.
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

final class ShareGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 16, height: 18)
    }

    override var strokeWidth: CGFloat {
        return 2
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        let box = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let trayTop = box.minY + box.height * 0.42
        let head = box.height * 0.2

        let path = UIBezierPath()
        path.move(to: CGPoint(x: box.minX, y: trayTop))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.addLine(to: CGPoint(x: box.maxX, y: trayTop))

        path.move(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.midX, y: box.maxY - box.height * 0.3))

        path.move(to: CGPoint(x: box.midX - head, y: box.minY + head))
        path.addLine(to: CGPoint(x: box.midX, y: box.minY))
        path.addLine(to: CGPoint(x: box.midX + head, y: box.minY + head))
        return path
    }
}

final class StopGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 13, height: 13)
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        return UIBezierPath(roundedRect: rect, cornerRadius: 2.5)
    }
}

final class PersonGlyphView: GlyphView {

    override var glyphSize: CGSize {
        return CGSize(width: 20, height: 20)
    }

    override var strokeWidth: CGFloat {
        return 1.5
    }

    override func path(in rect: CGRect) -> UIBezierPath {
        let box = rect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
        let center = CGPoint(x: box.midX, y: box.midY)
        let radius = box.width / 2

        let path = UIBezierPath(arcCenter: center,
                                radius: radius,
                                startAngle: 0,
                                endAngle: .pi * 2,
                                clockwise: true)
        path.append(UIBezierPath(arcCenter: CGPoint(x: center.x, y: center.y - radius * 0.083),
                                 radius: radius * 0.417,
                                 startAngle: 0,
                                 endAngle: .pi * 2,
                                 clockwise: true))

        let shouldersOffset = radius * 1.083
        let shouldersRadius = radius * 0.748
        let inner = radius - strokeWidth / 2
        let meetY = (shouldersOffset * shouldersOffset + inner * inner
                     - shouldersRadius * shouldersRadius) / (2 * shouldersOffset)
        let meetX = sqrt(max(inner * inner - meetY * meetY, 0))

        path.append(UIBezierPath(arcCenter: CGPoint(x: center.x, y: center.y + shouldersOffset),
                                 radius: shouldersRadius,
                                 startAngle: atan2(meetY - shouldersOffset, -meetX),
                                 endAngle: atan2(meetY - shouldersOffset, meetX),
                                 clockwise: true))
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

final class GlyphButton: UIControl, Themed {

    static let side: CGFloat = 44

    private let glyph: GlyphView
    private let prominent: Bool

    init(glyph: GlyphView, prominent: Bool = false) {
        self.glyph = glyph
        self.prominent = prominent
        super.init(frame: .zero)
        backgroundColor = .clear

        glyph.isUserInteractionEnabled = false
        glyph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: GlyphButton.side),
            heightAnchor.constraint(equalToConstant: GlyphButton.side),

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
        glyph.color = prominent ? palette.textPrimary : palette.textSecondary
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

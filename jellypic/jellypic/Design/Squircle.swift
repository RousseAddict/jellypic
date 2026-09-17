import UIKit

// LEGACY(ios12): CALayerCornerCurve.continuous does not exist, so the squircle is traced by hand. Freed at iOS 13.
enum Squircle {

    static let exponent: CGFloat = 4
    private static let samplesPerCorner = 16

    private enum Corner {
        case topRight
        case bottomRight
        case bottomLeft
        case topLeft
    }

    static func path(in rect: CGRect, cornerRadius: CGFloat) -> UIBezierPath {
        guard rect.width > 0, rect.height > 0 else { return UIBezierPath() }

        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        guard radius > 0 else { return UIBezierPath(rect: rect) }

        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        append(.topRight, to: path,
               center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius)
        append(.bottomRight, to: path,
               center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius)
        append(.bottomLeft, to: path,
               center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius)
        append(.topLeft, to: path,
               center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius)
        path.close()
        return path
    }

    private static func append(_ corner: Corner,
                               to path: UIBezierPath,
                               center: CGPoint,
                               radius: CGFloat) {
        let power = 2 / exponent
        for step in 0...samplesPerCorner {
            let angle = CGFloat(step) / CGFloat(samplesPerCorner) * (.pi / 2)
            let sine = pow(sin(angle), power)
            let cosine = pow(cos(angle), power)

            let offset: CGPoint
            switch corner {
            case .topRight:
                offset = CGPoint(x: sine, y: -cosine)
            case .bottomRight:
                offset = CGPoint(x: cosine, y: sine)
            case .bottomLeft:
                offset = CGPoint(x: -sine, y: cosine)
            case .topLeft:
                offset = CGPoint(x: -cosine, y: -sine)
            }

            path.addLine(to: CGPoint(x: center.x + offset.x * radius,
                                     y: center.y + offset.y * radius))
        }
    }
}

class SquircleView: UIView {

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    var cornerRadius: CGFloat = 16 {
        didSet { setNeedsLayout() }
    }

    var fillColor: UIColor = .clear {
        didSet { shapeLayer.fillColor = fillColor.cgColor }
    }

    var strokeColor: UIColor = .clear {
        didSet { shapeLayer.strokeColor = strokeColor.cgColor }
    }

    var strokeWidth: CGFloat = 0 {
        didSet { shapeLayer.lineWidth = strokeWidth }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shapeLayer.fillColor = fillColor.cgColor
        shapeLayer.strokeColor = strokeColor.cgColor
        shapeLayer.lineWidth = strokeWidth
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func applyShadow(_ palette: ThemePalette) {
        shapeLayer.shadowColor = palette.shadowColor.cgColor
        shapeLayer.shadowOpacity = palette.shadowOpacity
        shapeLayer.shadowRadius = palette.shadowRadius
        shapeLayer.shadowOffset = palette.shadowOffset
    }

    func removeShadow() {
        shapeLayer.shadowOpacity = 0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = Squircle.path(in: bounds, cornerRadius: cornerRadius).cgPath
        shapeLayer.path = path
        shapeLayer.shadowPath = path
    }
}

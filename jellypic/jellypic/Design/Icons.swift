import UIKit

final class CheckmarkView: UIView {

    override class var layerClass: AnyClass {
        return CAShapeLayer.self
    }

    private var shapeLayer: CAShapeLayer {
        return layer as! CAShapeLayer
    }

    var color: UIColor = .black {
        didSet { shapeLayer.strokeColor = color.cgColor }
    }

    var lineWidth: CGFloat = 2 {
        didSet { shapeLayer.lineWidth = lineWidth }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.strokeColor = color.cgColor
        shapeLayer.lineWidth = lineWidth
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 18, height: 18)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let height = bounds.height
        let path = UIBezierPath()
        path.move(to: CGPoint(x: width * 0.20, y: height * 0.53))
        path.addLine(to: CGPoint(x: width * 0.42, y: height * 0.74))
        path.addLine(to: CGPoint(x: width * 0.80, y: height * 0.28))
        shapeLayer.path = path.cgPath
    }

    func animateStroke() {
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0
        animation.toValue = 1
        animation.duration = 0.26
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shapeLayer.add(animation, forKey: "stroke")
    }
}

final class SelectionIndicatorView: UIView {

    private let ring = SquircleView()
    private let checkmark = CheckmarkView()

    var isOn: Bool = false {
        didSet {
            guard isOn != oldValue else { return }
            update()
            if isOn {
                checkmark.animateStroke()
            }
        }
    }

    private var palette = Theme.palette

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        ring.translatesAutoresizingMaskIntoConstraints = false
        checkmark.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ring)
        addSubview(checkmark)

        NSLayoutConstraint.activate([
            ring.topAnchor.constraint(equalTo: topAnchor),
            ring.leadingAnchor.constraint(equalTo: leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: trailingAnchor),
            ring.bottomAnchor.constraint(equalTo: bottomAnchor),
            checkmark.centerXAnchor.constraint(equalTo: centerXAnchor),
            checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkmark.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.72),
            checkmark.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.72)
        ])

        update()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 24, height: 24)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.cornerRadius = bounds.height / 2
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        update()
    }

    private func update() {
        ring.fillColor = isOn ? palette.accent : .clear
        ring.strokeColor = isOn ? palette.accent : palette.separator
        ring.strokeWidth = 1.5
        checkmark.color = palette.onAccent
        checkmark.isHidden = !isOn
    }
}

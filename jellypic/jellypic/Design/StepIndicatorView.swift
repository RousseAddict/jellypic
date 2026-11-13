import UIKit

final class CircleView: UIView {

    var fillColor: UIColor = .clear {
        didSet { backgroundColor = fillColor }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = fillColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

final class StepDotControl: UIControl {

    enum State {
        case current
        case reachable
        case upcoming
    }

    private static let diameter: CGFloat = 8
    private static let currentWidth: CGFloat = 20

    private let dot = CircleView()
    private var palette = Theme.palette
    private var dotState: State = .upcoming
    private var dotWidth: NSLayoutConstraint!

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.4 : 1 }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        dot.isUserInteractionEnabled = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        dotWidth = dot.widthAnchor.constraint(equalToConstant: StepDotControl.diameter)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dotWidth,
            dot.heightAnchor.constraint(equalToConstant: StepDotControl.diameter)
        ])

        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: 36, height: 44)
    }

    func setState(_ state: State) {
        dotState = state
        isUserInteractionEnabled = state == .reachable
        refresh()
    }

    func applyPalette(_ palette: ThemePalette) {
        self.palette = palette
        refresh()
    }

    private func refresh() {
        switch dotState {
        case .current:
            dot.fillColor = palette.accent
            dotWidth.constant = StepDotControl.currentWidth
        case .reachable:
            dot.fillColor = palette.textSecondary
            dotWidth.constant = StepDotControl.diameter
        case .upcoming:
            dot.fillColor = palette.separator
            dotWidth.constant = StepDotControl.diameter
        }
    }
}

final class StepIndicatorView: UIView, Themed {

    private let stack = UIStackView()
    private var dots: [StepDotControl] = []
    private var palette = Theme.palette

    var onSelect: ((Int) -> Void)?

    init(count: Int) {
        super.init(frame: .zero)
        backgroundColor = .clear

        stack.axis = .horizontal
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)
        ])

        for index in 0..<count {
            let dot = StepDotControl()
            dot.tag = index
            dot.addTarget(self, action: #selector(dotTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(dot)
            dots.append(dot)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    func update(current: Int, reachable: Int, animated: Bool) {
        let apply = {
            for (index, dot) in self.dots.enumerated() {
                if index == current {
                    dot.setState(.current)
                } else if index <= reachable {
                    dot.setState(.reachable)
                } else {
                    dot.setState(.upcoming)
                }
            }
            self.layoutIfNeeded()
        }

        guard animated else {
            apply()
            return
        }

        UIView.animate(withDuration: 0.24,
                       delay: 0,
                       options: [.beginFromCurrentState],
                       animations: apply,
                       completion: nil)
    }

    @objc private func dotTapped(_ sender: StepDotControl) {
        onSelect?(sender.tag)
    }

    func applyTheme(_ palette: ThemePalette) {
        self.palette = palette
        for dot in dots {
            dot.applyPalette(palette)
        }
    }
}

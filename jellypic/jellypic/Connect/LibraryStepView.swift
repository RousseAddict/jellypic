import UIKit

final class LibraryStepView: UIView, Themed {

    private static let rowHeight: CGFloat = 56
    private static let spacing: CGFloat = 6
    private static let maximumHeight: CGFloat = 240

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private var heightConstraint: NSLayoutConstraint!

    private var libraries: [JellyfinLibrary] = []
    private var rows: [OptionRowView] = []

    private(set) var selected: JellyfinLibrary?

    var onSelectionChange: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = LibraryStepView.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        emptyLabel.text = "No library on this server holds photos."
        emptyLabel.font = Typography.body
        emptyLabel.textAlignment = .center
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        heightConstraint = scrollView.heightAnchor.constraint(equalToConstant: LibraryStepView.rowHeight)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightConstraint,

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            emptyLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        applyTheme(Theme.palette)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func setLibraries(_ libraries: [JellyfinLibrary]) {
        self.libraries = libraries

        for row in rows {
            stack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rows = []

        for (index, library) in libraries.enumerated() {
            let row = OptionRowView()
            row.title = library.name
            row.tag = index
            row.addTarget(self, action: #selector(rowTapped(_:)), for: .touchUpInside)
            row.heightAnchor.constraint(equalToConstant: LibraryStepView.rowHeight).isActive = true
            stack.addArrangedSubview(row)
            rows.append(row)
        }

        emptyLabel.isHidden = !libraries.isEmpty
        scrollView.isHidden = libraries.isEmpty

        let count = CGFloat(libraries.count)
        let total = count * LibraryStepView.rowHeight + max(count - 1, 0) * LibraryStepView.spacing
        heightConstraint.constant = min(max(total, LibraryStepView.rowHeight), LibraryStepView.maximumHeight)

        select(index: libraries.isEmpty ? nil : 0)
    }

    private func select(index: Int?) {
        for (position, row) in rows.enumerated() {
            row.isOn = position == index
        }
        if let index = index {
            selected = libraries[index]
        } else {
            selected = nil
        }
        onSelectionChange?()
    }

    @objc private func rowTapped(_ sender: OptionRowView) {
        select(index: sender.tag)
    }

    func applyTheme(_ palette: ThemePalette) {
        emptyLabel.textColor = palette.textSecondary
    }
}

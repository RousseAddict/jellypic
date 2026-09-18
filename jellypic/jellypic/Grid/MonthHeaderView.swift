import UIKit

final class MonthHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "MonthHeaderView"
    static let height: CGFloat = 44

    private let label = UILabel()
    private var leading: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)

        label.font = Typography.headline
        label.adjustsFontForContentSizeCategory = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        leading = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)

        NSLayoutConstraint.activate([
            leading,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(monthKey: String, palette: ThemePalette, leadingInset: CGFloat) {
        leading.constant = 16 + leadingInset
        backgroundColor = palette.background
        label.textColor = palette.textPrimary
        label.text = MonthKey.title(for: monthKey)
    }
}

extension MonthKey {

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    static func title(for monthKey: String) -> String {
        guard let date = parser.date(from: monthKey) else { return "Undated" }
        return displayFormatter.string(from: date)
    }

    static func shortTitle(for monthKey: String) -> String {
        guard let date = parser.date(from: monthKey) else { return "Undated" }
        return shortFormatter.string(from: date)
    }
}

import UIKit

final class RootViewController: UIViewController {

    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "jellypic"

        // LEGACY(ios12): semantic colours are iOS 13+. Freed at iOS 13.
        view.backgroundColor = .white

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = """
        jellypic
        \(Self.runningOSDescription())
        """
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
        ])
    }

    private static func runningOSDescription() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "running on iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}

import UIKit

enum ThemeMode: Int {
    case system
    case light
    case dark
}

struct ThemePalette {
    let background: UIColor
    let surface: UIColor
    let field: UIColor
    let textPrimary: UIColor
    let textSecondary: UIColor
    let separator: UIColor
    let accent: UIColor
    let onAccent: UIColor
    let danger: UIColor
    let shadowColor: UIColor
    let shadowOpacity: Float
    let shadowRadius: CGFloat
    let shadowOffset: CGSize
}

enum Theme {

    static let didChangeNotification = Notification.Name("jellypic.themeDidChange")

    static var mode: ThemeMode {
        get { return Preferences.themeMode }
        set {
            Preferences.themeMode = newValue
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var palette: ThemePalette {
        return isDark ? dark : light
    }

    static var isDark: Bool {
        switch mode {
        case .light:
            return false
        case .dark:
            return true
        case .system:
            // LEGACY(ios12): userInterfaceStyle does not exist, light is the only possible answer. Freed at iOS 13.
            if #available(iOS 13.0, *) {
                return UIScreen.main.traitCollection.userInterfaceStyle == .dark
            }
            return false
        }
    }

    private static let light = ThemePalette(
        background: UIColor(hex: 0xF7F7F8),
        surface: UIColor(hex: 0xFFFFFF),
        field: UIColor(hex: 0xF2F2F4),
        textPrimary: UIColor(hex: 0x0B0B0C),
        textSecondary: UIColor(hex: 0x7A7A80),
        separator: UIColor(hex: 0xE6E6E9),
        accent: UIColor(hex: 0x0B0B0C),
        onAccent: UIColor(hex: 0xFFFFFF),
        danger: UIColor(hex: 0xC2362B),
        shadowColor: UIColor(hex: 0x0B0B0C),
        shadowOpacity: 0.10,
        shadowRadius: 24,
        shadowOffset: CGSize(width: 0, height: 10)
    )

    private static let dark = ThemePalette(
        background: UIColor(hex: 0x0B0B0C),
        surface: UIColor(hex: 0x1A1A1C),
        field: UIColor(hex: 0x232326),
        textPrimary: UIColor(hex: 0xF2F2F4),
        textSecondary: UIColor(hex: 0x8E8E95),
        separator: UIColor(hex: 0x2A2A2E),
        accent: UIColor(hex: 0xF2F2F4),
        onAccent: UIColor(hex: 0x0B0B0C),
        danger: UIColor(hex: 0xF4A6A0),
        shadowColor: UIColor(hex: 0x000000),
        shadowOpacity: 0.55,
        shadowRadius: 28,
        shadowOffset: CGSize(width: 0, height: 12)
    )
}

enum Typography {

    static var title: UIFont {
        return scaled(size: 28, weight: .semibold, style: .title1)
    }

    static var headline: UIFont {
        return scaled(size: 17, weight: .semibold, style: .headline)
    }

    static var body: UIFont {
        return scaled(size: 16, weight: .regular, style: .body)
    }

    static var caption: UIFont {
        return scaled(size: 13, weight: .regular, style: .footnote)
    }

    static var button: UIFont {
        return scaled(size: 17, weight: .semibold, style: .headline)
    }

    private static func scaled(size: CGFloat,
                               weight: UIFont.Weight,
                               style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        let red = CGFloat((hex & 0xFF0000) >> 16) / 255
        let green = CGFloat((hex & 0x00FF00) >> 8) / 255
        let blue = CGFloat(hex & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}

protocol Themed {
    func applyTheme(_ palette: ThemePalette)
}

extension UIView {
    func applyThemeRecursively(_ palette: ThemePalette) {
        if let themed = self as? Themed {
            themed.applyTheme(palette)
        }
        for subview in subviews {
            subview.applyThemeRecursively(palette)
        }
    }
}

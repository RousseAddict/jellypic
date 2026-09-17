import Foundation

enum Preferences {

    private enum Key {
        static let themeMode = "themeMode"
        static let libraryId = "libraryId"
        static let libraryName = "libraryName"
    }

    private static let defaults = UserDefaults.standard

    static var themeMode: ThemeMode {
        get {
            guard let raw = defaults.object(forKey: Key.themeMode) as? Int,
                  let mode = ThemeMode(rawValue: raw) else { return .system }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.themeMode) }
    }

    static var libraryId: String? {
        get { return defaults.string(forKey: Key.libraryId) }
        set { defaults.set(newValue, forKey: Key.libraryId) }
    }

    static var libraryName: String? {
        get { return defaults.string(forKey: Key.libraryName) }
        set { defaults.set(newValue, forKey: Key.libraryName) }
    }

    static func clearLibrary() {
        defaults.removeObject(forKey: Key.libraryId)
        defaults.removeObject(forKey: Key.libraryName)
    }
}

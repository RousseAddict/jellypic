import Foundation

enum Preferences {

    private enum Key {
        static let themeMode = "themeMode"
        static let libraryId = "libraryId"
        static let libraryName = "libraryName"
        static let syncLibraryId = "syncLibraryId"
        static let syncStartIndex = "syncStartIndex"
        static let syncTotal = "syncTotal"
        static let syncCompleted = "syncCompleted"
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

    static var syncLibraryId: String? {
        get { return defaults.string(forKey: Key.syncLibraryId) }
        set { defaults.set(newValue, forKey: Key.syncLibraryId) }
    }

    static var syncStartIndex: Int {
        get { return defaults.integer(forKey: Key.syncStartIndex) }
        set { defaults.set(newValue, forKey: Key.syncStartIndex) }
    }

    static var syncTotal: Int {
        get { return defaults.integer(forKey: Key.syncTotal) }
        set { defaults.set(newValue, forKey: Key.syncTotal) }
    }

    static var syncCompleted: Bool {
        get { return defaults.bool(forKey: Key.syncCompleted) }
        set { defaults.set(newValue, forKey: Key.syncCompleted) }
    }

    static func clearSync() {
        defaults.removeObject(forKey: Key.syncLibraryId)
        defaults.removeObject(forKey: Key.syncStartIndex)
        defaults.removeObject(forKey: Key.syncTotal)
        defaults.removeObject(forKey: Key.syncCompleted)
    }

    static func clearLibrary() {
        defaults.removeObject(forKey: Key.libraryId)
        defaults.removeObject(forKey: Key.libraryName)
        clearSync()
    }
}

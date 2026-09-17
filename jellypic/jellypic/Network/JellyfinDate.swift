import Foundation

enum JellyfinDate {

    static func parse(_ raw: String) -> Date? {
        let normalized = normalize(raw)
        if let date = fractional.date(from: normalized) {
            return date
        }
        return plain.date(from: normalized)
    }

    static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return value }

        var zone = ""
        if value.hasSuffix("Z") || value.hasSuffix("z") {
            zone = "Z"
            value.removeLast()
        } else if let plus = value.range(of: "+", options: .backwards)?.lowerBound {
            zone = String(value[plus...])
            value = String(value[..<plus])
        } else if let separator = value.firstIndex(of: "T"),
                  let minus = value.range(of: "-",
                                          options: .backwards,
                                          range: separator..<value.endIndex)?.lowerBound {
            zone = String(value[minus...])
            value = String(value[..<minus])
        }
        if zone.isEmpty {
            zone = "Z"
        }

        if let dot = value.firstIndex(of: ".") {
            let start = value.index(after: dot)
            var digits = String(value[start...].prefix(3))
            if digits.isEmpty {
                value = String(value[..<dot])
            } else {
                while digits.count < 3 {
                    digits.append("0")
                }
                value = String(value[..<start]) + digits
            }
        }

        return value + zone
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

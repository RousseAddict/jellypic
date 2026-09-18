import Foundation

enum ServerURL {

    static let defaultPort = 8096

    static func candidates(from input: String) -> [URL] {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard !text.isEmpty else { return [] }

        if !text.contains("://") {
            text = "http://" + text
        }

        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else { return [] }

        var result: [URL] = [url]
        if url.port == nil,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.port = defaultPort
            if let withPort = components.url {
                result.append(withPort)
            }
        }
        return result
    }

    static func isPlaintextToPublicHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http",
              let host = url.host?.lowercased() else { return false }
        return !isPrivate(host)
    }

    private static func isPrivate(_ host: String) -> Bool {
        if host == "localhost" || !host.contains(".") {
            return !host.isEmpty
        }
        for suffix in [".local", ".lan", ".home.arpa", ".internal"] where host.hasSuffix(suffix) {
            return true
        }

        if host.contains(":") {
            if host == "::1" { return true }
            if host.hasPrefix("fc") || host.hasPrefix("fd") { return true }
            return host.hasPrefix("fe8") || host.hasPrefix("fe9")
                || host.hasPrefix("fea") || host.hasPrefix("feb")
        }

        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }

        switch (octets[0], octets[1]) {
        case (10, _), (127, _):
            return true
        case (192, 168), (169, 254):
            return true
        case (172, 16...31):
            return true
        default:
            return false
        }
    }
}

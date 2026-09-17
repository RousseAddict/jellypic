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

        var result = [url]
        if url.port == nil,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.port = defaultPort
            if let withPort = components.url {
                result.append(withPort)
            }
        }
        return result
    }
}

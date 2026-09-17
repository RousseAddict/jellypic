import Foundation

enum JellyfinError: Error {
    case invalidServerURL
    case notAJellyfinServer
    case appTransportSecurity
    case unreachable(URLError)
    case transport(Error)
    case unauthorized
    case httpStatus(Int)
    case emptyResponse
    case decoding(Error)
    case notAuthenticated
}

extension JellyfinError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "That does not look like a server address."
        case .notAJellyfinServer:
            return "Something answered at that address, but it is not a Jellyfin server."
        case .appTransportSecurity:
            return "iOS refused the connection because it is not HTTPS. Plain HTTP is allowed only on a local network."
        case .unreachable:
            return "Could not reach the server. Check the address, and that jellypic is allowed to access the local network."
        case .transport(let error):
            return error.localizedDescription
        case .unauthorized:
            return "Wrong username or password."
        case .httpStatus(let code):
            return "The server answered with HTTP \(code)."
        case .emptyResponse:
            return "The server answered with an empty response."
        case .decoding:
            return "The server answered in a format jellypic does not understand."
        case .notAuthenticated:
            return "Not signed in."
        }
    }
}

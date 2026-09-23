import Foundation

func jellyfinAuthorization(identity: DeviceIdentity, token: String?) -> String {
    var fields: [String] = []
    if let token = token {
        fields.append("Token=\"\(jellyfinHeaderValue(token))\"")
    }
    fields.append("Client=\"\(jellyfinHeaderValue(identity.client))\"")
    fields.append("Device=\"\(jellyfinHeaderValue(identity.device))\"")
    fields.append("DeviceId=\"\(jellyfinHeaderValue(identity.deviceId))\"")
    fields.append("Version=\"\(jellyfinHeaderValue(identity.version))\"")
    return "MediaBrowser " + fields.joined(separator: ", ")
}

private func jellyfinHeaderValue(_ value: String) -> String {
    let forbidden = CharacterSet(charactersIn: "\"\\,\r\n")
    let cleaned = value.components(separatedBy: forbidden).joined()
    return cleaned.isEmpty ? "unknown" : cleaned
}

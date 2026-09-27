import Foundation

struct LenientDate: Decodable {
    let value: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let raw = try? container.decode(String.self) else {
            value = nil
            return
        }
        value = JellyfinDate.parse(raw)
    }
}

struct PublicSystemInfo: Decodable {
    let id: String?
    let serverName: String?
    let version: String?
    let productName: String?
    let startupWizardCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
        case startupWizardCompleted = "StartupWizardCompleted"
    }
}

struct JellyfinUser: Decodable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
    }
}

struct AuthenticationResult: Decodable {
    let accessToken: String
    let serverId: String?
    let user: JellyfinUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case serverId = "ServerId"
        case user = "User"
    }
}

struct JellyfinLibrary: Decodable {
    let id: String
    let name: String
    let collectionType: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
    }

    var holdsPhotos: Bool {
        switch collectionType?.lowercased() {
        case "photos", "homevideos":
            return true
        default:
            return false
        }
    }
}

struct PhotoDTO: Decodable {
    let id: String
    let name: String?
    let type: String?
    let premiereDate: LenientDate?
    let dateCreated: LenientDate?
    let runTimeTicks: Int64?
    let width: Int?
    let height: Int?
    let latitude: Double?
    let longitude: Double?
    let imageTags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case runTimeTicks = "RunTimeTicks"
        case width = "Width"
        case height = "Height"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case imageTags = "ImageTags"
    }

    var captureDate: Date? {
        return premiereDate?.value ?? dateCreated?.value
    }

    var isVideo: Bool {
        return type == "Video"
    }

    var durationSeconds: Double {
        guard let ticks = runTimeTicks, ticks > 0 else { return 0 }
        return Double(ticks) / 10_000_000
    }

    var primaryImageTag: String? {
        return imageTags?["Primary"]
    }
}

struct PhotoPage {
    let items: [PhotoDTO]
    let totalRecordCount: Int
    let serverDate: Date?
}

struct PhotoDetailsDTO: Decodable {
    let name: String?
    let path: String?
    let container: String?
    let premiereDate: LenientDate?
    let dateCreated: LenientDate?
    let width: Int?
    let height: Int?
    let cameraMake: String?
    let cameraModel: String?
    let software: String?
    let exposureTime: Double?
    let shutterSpeed: Double?
    let aperture: Double?
    let focalLength: Double?
    let isoSpeedRating: Int?
    let latitude: Double?
    let longitude: Double?
    let altitude: Double?

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case path = "Path"
        case container = "Container"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case width = "Width"
        case height = "Height"
        case cameraMake = "CameraMake"
        case cameraModel = "CameraModel"
        case software = "Software"
        case exposureTime = "ExposureTime"
        case shutterSpeed = "ShutterSpeed"
        case aperture = "Aperture"
        case focalLength = "FocalLength"
        case isoSpeedRating = "IsoSpeedRating"
        case latitude = "Latitude"
        case longitude = "Longitude"
        case altitude = "Altitude"
    }

    var captureDate: Date? {
        return premiereDate?.value ?? dateCreated?.value
    }

    var fileName: String? {
        guard let path = path, !path.isEmpty else { return name.flatMap(PhotoDetailsDTO.safeFileName) }
        return PhotoDetailsDTO.safeFileName((path as NSString).lastPathComponent)
    }

    private static func safeFileName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\") else { return nil }
        return trimmed
    }

    var fNumber: Double? {
        guard let aperture = aperture, aperture > 0 else { return nil }
        return pow(2, aperture / 2)
    }

    var exposureSeconds: Double? {
        if let exposureTime = exposureTime, exposureTime > 0 {
            return exposureTime
        }
        guard let shutterSpeed = shutterSpeed else { return nil }
        return 1 / pow(2, shutterSpeed)
    }
}

struct MediaSourceDTO: Decodable {
    let id: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let transcodingUrl: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingUrl = "TranscodingUrl"
    }

    var transcodeReasons: [String] {
        guard let raw = transcodingUrl,
              let components = URLComponents(string: raw),
              let value = components.queryItems?.first(where: {
                  $0.name.caseInsensitiveCompare("TranscodeReasons") == .orderedSame
              })?.value else { return [] }
        return value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct PlaybackInfoResponse: Decodable {
    let mediaSources: [MediaSourceDTO]
    let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionId = "PlaySessionId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaSources = try container.decodeIfPresent([MediaSourceDTO].self, forKey: .mediaSources) ?? []
        playSessionId = try container.decodeIfPresent(String.self, forKey: .playSessionId)
    }
}

struct QueryResult<Element: Decodable>: Decodable {
    let items: [Element]
    let totalRecordCount: Int
    let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Element].self, forKey: .items) ?? []
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount) ?? items.count
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex) ?? 0
    }
}

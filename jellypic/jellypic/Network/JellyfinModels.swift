import Foundation

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
        return collectionType?.lowercased() == "homevideos"
    }
}

struct PhotoDTO: Decodable {
    let id: String
    let name: String?
    let premiereDate: Date?
    let dateCreated: Date?
    let width: Int?
    let height: Int?
    let imageTags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case width = "Width"
        case height = "Height"
        case imageTags = "ImageTags"
    }

    var captureDate: Date? {
        return premiereDate ?? dateCreated
    }

    var primaryImageTag: String? {
        return imageTags?["Primary"]
    }
}

struct PhotoDetailsDTO: Decodable {
    let name: String?
    let path: String?
    let container: String?
    let premiereDate: Date?
    let dateCreated: Date?
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
        return premiereDate ?? dateCreated
    }

    var fileName: String? {
        guard let path = path, !path.isEmpty else { return name }
        return (path as NSString).lastPathComponent
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

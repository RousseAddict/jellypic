import CoreData

final class PhotoItem: NSManagedObject {

    static let entityName = "PhotoItem"

    @NSManaged var id: String
    @NSManaged var name: String?
    @NSManaged var captureDate: Date?
    @NSManaged var monthKey: String
    @NSManaged var imageTag: String?
    @NSManaged var width: Int32
    @NSManaged var height: Int32
    @NSManaged var latitude: NSNumber?
    @NSManaged var longitude: NSNumber?
    @NSManaged var isVideo: Bool
    @NSManaged var duration: Double
}

enum PhotoModel {

    static let schemaVersion = 4

    static func make() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = PhotoItem.entityName
        entity.managedObjectClassName = NSStringFromClass(PhotoItem.self)

        let id = attribute("id", .stringAttributeType, optional: false)
        let name = attribute("name", .stringAttributeType)
        let captureDate = attribute("captureDate", .dateAttributeType)
        let monthKey = attribute("monthKey", .stringAttributeType, optional: false)
        monthKey.defaultValue = ""
        let imageTag = attribute("imageTag", .stringAttributeType)
        let width = attribute("width", .integer32AttributeType, optional: false)
        width.defaultValue = 0
        let height = attribute("height", .integer32AttributeType, optional: false)
        height.defaultValue = 0
        let latitude = attribute("latitude", .doubleAttributeType)
        let longitude = attribute("longitude", .doubleAttributeType)
        let isVideo = attribute("isVideo", .booleanAttributeType, optional: false)
        isVideo.defaultValue = false
        let duration = attribute("duration", .doubleAttributeType, optional: false)
        duration.defaultValue = 0

        entity.properties = [id, name, captureDate, monthKey, imageTag, width, height,
                             latitude, longitude, isVideo, duration]

        let idIndex = NSFetchIndexDescription(name: "byId",
                                              elements: [NSFetchIndexElementDescription(property: id,
                                                                                        collationType: .binary)])
        let timelineIndex = NSFetchIndexDescription(name: "byTimeline",
                                                    elements: [NSFetchIndexElementDescription(property: monthKey,
                                                                                              collationType: .binary),
                                                               NSFetchIndexElementDescription(property: captureDate,
                                                                                              collationType: .binary),
                                                               NSFetchIndexElementDescription(property: id,
                                                                                              collationType: .binary)])
        entity.indexes = [idIndex, timelineIndex]

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    private static func attribute(_ name: String,
                                  _ type: NSAttributeType,
                                  optional: Bool = true) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

enum MonthKey {

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter
    }()

    private static let shortFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter
    }()

    static func make(from date: Date?) -> String {
        guard let date = date else { return "" }
        return formatter.string(from: date)
    }

    static func title(for monthKey: String) -> String {
        return localized(monthKey, using: displayFormatter)
    }

    static func shortTitle(for monthKey: String) -> String {
        return localized(monthKey, using: shortFormatter)
    }

    private static func localized(_ monthKey: String, using output: DateFormatter) -> String {
        guard let date = formatter.date(from: monthKey) else { return "Undated" }
        return output.string(from: date)
    }
}

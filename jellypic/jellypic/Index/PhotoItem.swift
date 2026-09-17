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
}

enum PhotoModel {

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

        entity.properties = [id, name, captureDate, monthKey, imageTag, width, height]

        let idIndex = NSFetchIndexDescription(name: "byId",
                                              elements: [NSFetchIndexElementDescription(property: id,
                                                                                        collationType: .binary)])
        let dateIndex = NSFetchIndexDescription(name: "byCaptureDate",
                                                elements: [NSFetchIndexElementDescription(property: captureDate,
                                                                                          collationType: .binary)])
        entity.indexes = [idIndex, dateIndex]

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

    static func make(from date: Date?) -> String {
        guard let date = date else { return "" }
        return formatter.string(from: date)
    }
}

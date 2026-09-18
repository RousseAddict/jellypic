import CoreData

// LEGACY(ios12): Core Data stands in for SwiftData. Freed at iOS 17.
final class PhotoStore {

    static let didResetNotification = Notification.Name("PhotoStoreDidReset")

    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext

    private var viewContext: NSManagedObjectContext {
        return container.viewContext
    }

    init(name: String = "JellyPicIndex") {
        let container = NSPersistentContainer(name: name, managedObjectModel: PhotoModel.make())
        PhotoStore.load(container)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let background = container.newBackgroundContext()
        background.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        background.undoManager = nil

        self.container = container
        self.backgroundContext = background
    }

    func makeTimelineResults() -> NSFetchedResultsController<PhotoItem> {
        let request = NSFetchRequest<PhotoItem>(entityName: PhotoItem.entityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(PhotoItem.monthKey), ascending: false),
            NSSortDescriptor(key: #keyPath(PhotoItem.captureDate), ascending: false),
            NSSortDescriptor(key: #keyPath(PhotoItem.id), ascending: false)
        ]
        request.fetchBatchSize = 60
        request.returnsObjectsAsFaults = false

        return NSFetchedResultsController(fetchRequest: request,
                                          managedObjectContext: viewContext,
                                          sectionNameKeyPath: #keyPath(PhotoItem.monthKey),
                                          cacheName: nil)
    }

    func performBackground(_ block: @escaping (NSManagedObjectContext) -> Void) {
        backgroundContext.perform {
            block(self.backgroundContext)
        }
    }

    func upsert(_ photos: [PhotoDTO], in context: NSManagedObjectContext) throws {
        guard !photos.isEmpty else { return }

        let request = NSFetchRequest<PhotoItem>(entityName: PhotoItem.entityName)
        request.predicate = NSPredicate(format: "id IN %@", photos.map { $0.id })
        request.returnsObjectsAsFaults = false

        var existing: [String: PhotoItem] = [:]
        for item in try context.fetch(request) {
            existing[item.id] = item
        }

        for photo in photos {
            let item = existing[photo.id]
                ?? (NSEntityDescription.insertNewObject(forEntityName: PhotoItem.entityName,
                                                        into: context) as! PhotoItem)
            item.id = photo.id
            item.name = photo.name
            item.captureDate = photo.captureDate
            item.monthKey = MonthKey.make(from: photo.captureDate)
            item.imageTag = photo.primaryImageTag
            item.width = Int32(photo.width ?? 0)
            item.height = Int32(photo.height ?? 0)
        }

        try context.save()
        context.reset()
    }

    func count() -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: PhotoItem.entityName)
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    func reset() {
        var deleted: [NSManagedObjectID] = []

        backgroundContext.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: PhotoItem.entityName)
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            delete.resultType = .resultTypeObjectIDs
            let result = try? self.backgroundContext.execute(delete)
            deleted = ((result as? NSBatchDeleteResult)?.result as? [NSManagedObjectID]) ?? []
            self.backgroundContext.reset()
        }

        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: deleted],
                                            into: [container.viewContext])
        NotificationCenter.default.post(name: PhotoStore.didResetNotification, object: self)
    }

    private static func load(_ container: NSPersistentContainer) {
        let url = container.persistentStoreDescriptions.first?.url

        if Preferences.indexSchemaVersion != PhotoModel.schemaVersion, let url = url {
            destroy(container, at: url)
        }

        var failure: Error?
        container.loadPersistentStores { _, error in
            failure = error
        }
        if failure != nil, let url = url {
            destroy(container, at: url)
            container.loadPersistentStores { _, error in failure = error }
        }

        if failure == nil {
            Preferences.indexSchemaVersion = PhotoModel.schemaVersion
        }
    }

    private static func destroy(_ container: NSPersistentContainer, at url: URL) {
        try? container.persistentStoreCoordinator.destroyPersistentStore(at: url,
                                                                         ofType: NSSQLiteStoreType,
                                                                         options: nil)
        Preferences.clearSync()
    }
}

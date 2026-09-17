import CoreData

final class PhotoStore {

    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext

    var viewContext: NSManagedObjectContext {
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
        backgroundContext.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: PhotoItem.entityName)
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            _ = try? self.backgroundContext.execute(delete)
            self.backgroundContext.reset()
        }
        container.viewContext.reset()
    }

    private static func load(_ container: NSPersistentContainer) {
        var failure: Error?
        container.loadPersistentStores { _, error in
            failure = error
        }
        guard failure != nil, let url = container.persistentStoreDescriptions.first?.url else { return }

        try? container.persistentStoreCoordinator.destroyPersistentStore(at: url,
                                                                        ofType: NSSQLiteStoreType,
                                                                        options: nil)
        container.loadPersistentStores { _, _ in }
    }
}

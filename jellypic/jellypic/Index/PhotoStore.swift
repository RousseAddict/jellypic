import CoreData

struct Photo {
    let id: String
    let imageTag: String?
    let captureDate: Date?
}

protocol PhotoTimeline: AnyObject {
    var sectionCount: Int { get }
    var isEmpty: Bool { get }
    var onChange: (() -> Void)? { get set }
    var onReset: (() -> Void)? { get set }

    func numberOfPhotos(inSection section: Int) -> Int
    func monthKey(forSection section: Int) -> String
    func photo(at indexPath: IndexPath) -> Photo
    func indexPath(forPhotoId id: String) -> IndexPath?
}

extension PhotoTimeline {

    func photoIfPresent(at indexPath: IndexPath) -> Photo? {
        guard indexPath.section < sectionCount,
              indexPath.item < numberOfPhotos(inSection: indexPath.section) else { return nil }
        return photo(at: indexPath)
    }
}

final class PhotoListTimeline: PhotoTimeline {

    private let photos: [Photo]

    var onChange: (() -> Void)?
    var onReset: (() -> Void)?

    init(photos: [Photo]) {
        self.photos = photos
    }

    var sectionCount: Int {
        return photos.isEmpty ? 0 : 1
    }

    var isEmpty: Bool {
        return photos.isEmpty
    }

    func numberOfPhotos(inSection section: Int) -> Int {
        return photos.count
    }

    func monthKey(forSection section: Int) -> String {
        return ""
    }

    func photo(at indexPath: IndexPath) -> Photo {
        return photos[indexPath.item]
    }

    func indexPath(forPhotoId id: String) -> IndexPath? {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
        return IndexPath(item: index, section: 0)
    }
}

struct PhotoLocation {
    let photo: Photo
    let latitude: Double
    let longitude: Double
}

protocol PhotoStore: AnyObject {
    func makeTimeline() -> PhotoTimeline
    func upsert(_ photos: [PhotoDTO], completion: @escaping (Error?) -> Void)
    func count() -> Int
    func locations(completion: @escaping ([PhotoLocation]) -> Void)
    func reset()
}

private let photoStoreDidReset = Notification.Name("PhotoStoreDidReset")

// LEGACY(ios12): Core Data stands in for SwiftData. Freed at iOS 17.
final class CoreDataPhotoStore: PhotoStore {

    private let container: NSPersistentContainer
    private let backgroundContext: NSManagedObjectContext

    init(name: String = "JellyPicIndex") {
        let container = NSPersistentContainer(name: name, managedObjectModel: PhotoModel.make())
        CoreDataPhotoStore.load(container)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        let background = container.newBackgroundContext()
        background.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        background.undoManager = nil

        self.container = container
        self.backgroundContext = background
    }

    func makeTimeline() -> PhotoTimeline {
        let request = NSFetchRequest<PhotoItem>(entityName: PhotoItem.entityName)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(PhotoItem.monthKey), ascending: false),
            NSSortDescriptor(key: #keyPath(PhotoItem.captureDate), ascending: false),
            NSSortDescriptor(key: #keyPath(PhotoItem.id), ascending: false)
        ]
        request.fetchBatchSize = 60
        request.returnsObjectsAsFaults = false

        let controller = NSFetchedResultsController(fetchRequest: request,
                                                    managedObjectContext: container.viewContext,
                                                    sectionNameKeyPath: #keyPath(PhotoItem.monthKey),
                                                    cacheName: nil)
        return CoreDataTimeline(controller: controller)
    }

    func upsert(_ photos: [PhotoDTO], completion: @escaping (Error?) -> Void) {
        backgroundContext.perform {
            var failure: Error?
            do {
                try self.write(photos, in: self.backgroundContext)
            } catch {
                failure = error
            }
            DispatchQueue.main.async { completion(failure) }
        }
    }

    func count() -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: PhotoItem.entityName)
        return (try? container.viewContext.count(for: request)) ?? 0
    }

    func locations(completion: @escaping ([PhotoLocation]) -> Void) {
        let context = container.newBackgroundContext()
        context.perform {
            let request = NSFetchRequest<NSDictionary>(entityName: PhotoItem.entityName)
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = [#keyPath(PhotoItem.id),
                                         #keyPath(PhotoItem.imageTag),
                                         #keyPath(PhotoItem.captureDate),
                                         #keyPath(PhotoItem.latitude),
                                         #keyPath(PhotoItem.longitude)]
            request.sortDescriptors = [
                NSSortDescriptor(key: #keyPath(PhotoItem.captureDate), ascending: false),
                NSSortDescriptor(key: #keyPath(PhotoItem.id), ascending: false)
            ]
            request.predicate = NSPredicate(format: "latitude != nil AND longitude != nil")

            let rows = (try? context.fetch(request)) ?? []
            var locations: [PhotoLocation] = []
            locations.reserveCapacity(rows.count)
            for row in rows {
                guard let id = row[#keyPath(PhotoItem.id)] as? String,
                      let latitude = row[#keyPath(PhotoItem.latitude)] as? Double,
                      let longitude = row[#keyPath(PhotoItem.longitude)] as? Double else { continue }
                let photo = Photo(id: id,
                                  imageTag: row[#keyPath(PhotoItem.imageTag)] as? String,
                                  captureDate: row[#keyPath(PhotoItem.captureDate)] as? Date)
                locations.append(PhotoLocation(photo: photo,
                                               latitude: latitude,
                                               longitude: longitude))
            }
            DispatchQueue.main.async { completion(locations) }
        }
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
        NotificationCenter.default.post(name: photoStoreDidReset, object: self)
    }

    private func write(_ photos: [PhotoDTO], in context: NSManagedObjectContext) throws {
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
            item.latitude = photo.latitude.map { NSNumber(value: $0) }
            item.longitude = photo.longitude.map { NSNumber(value: $0) }
        }

        try context.save()
        context.reset()
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

final class CoreDataTimeline: NSObject, PhotoTimeline {

    private let controller: NSFetchedResultsController<PhotoItem>

    var onChange: (() -> Void)?
    var onReset: (() -> Void)?

    init(controller: NSFetchedResultsController<PhotoItem>) {
        self.controller = controller
        super.init()

        controller.delegate = self
        try? controller.performFetch()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(storeDidReset),
                                               name: photoStoreDidReset,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var sectionCount: Int {
        return controller.sections?.count ?? 0
    }

    var isEmpty: Bool {
        return controller.fetchedObjects?.isEmpty ?? true
    }

    func numberOfPhotos(inSection section: Int) -> Int {
        return controller.sections?[section].numberOfObjects ?? 0
    }

    func monthKey(forSection section: Int) -> String {
        guard section < sectionCount else { return "" }
        return controller.sections?[section].name ?? ""
    }

    func photo(at indexPath: IndexPath) -> Photo {
        let item = controller.object(at: indexPath)
        return Photo(id: item.id, imageTag: item.imageTag, captureDate: item.captureDate)
    }

    func indexPath(forPhotoId id: String) -> IndexPath? {
        let request = NSFetchRequest<PhotoItem>(entityName: PhotoItem.entityName)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        guard let item = try? controller.managedObjectContext.fetch(request).first else { return nil }
        return controller.indexPath(forObject: item)
    }

    @objc private func storeDidReset() {
        try? controller.performFetch()
        onReset?()
    }
}

extension CoreDataTimeline: NSFetchedResultsControllerDelegate {

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        onChange?()
    }
}

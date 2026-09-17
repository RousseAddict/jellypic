import Foundation

final class SyncEngine {

    struct Progress {
        let indexed: Int
        let total: Int
    }

    static let pageSize = 200

    private let client: JellyfinAPI
    private let store: PhotoStore

    private(set) var isRunning = false
    private var isCancelled = false
    private var libraryId: String = ""

    var onProgress: ((Progress) -> Void)?
    var onFinish: ((JellyfinError?) -> Void)?

    init(client: JellyfinAPI, store: PhotoStore) {
        self.client = client
        self.store = store
    }

    func start(libraryId: String) {
        guard !isRunning else { return }

        if Preferences.syncLibraryId != libraryId {
            store.reset()
            Preferences.clearSync()
            Preferences.syncLibraryId = libraryId
        }

        guard !Preferences.syncCompleted else {
            onFinish?(nil)
            return
        }

        self.libraryId = libraryId
        isRunning = true
        isCancelled = false
        requestPage(at: Preferences.syncStartIndex, includeTotalCount: true)
    }

    func refresh(libraryId: String) {
        guard !isRunning else { return }
        Preferences.syncStartIndex = 0
        Preferences.syncCompleted = false
        start(libraryId: libraryId)
    }

    func cancel() {
        isCancelled = true
    }

    private func requestPage(at startIndex: Int, includeTotalCount: Bool) {
        client.photos(libraryId: libraryId,
                      startIndex: startIndex,
                      limit: SyncEngine.pageSize,
                      includeTotalCount: includeTotalCount) { [weak self] result in
            guard let self = self else { return }
            guard !self.isCancelled else {
                self.stop(with: nil)
                return
            }
            switch result {
            case .failure(let error):
                self.stop(with: error)
            case .success(let page):
                if includeTotalCount {
                    Preferences.syncTotal = page.totalRecordCount
                }
                self.persist(page, from: startIndex)
            }
        }
    }

    private func persist(_ page: QueryResult<PhotoDTO>, from startIndex: Int) {
        store.performBackground { [weak self] context in
            guard let self = self else { return }
            do {
                try self.store.upsert(page.items, in: context)
            } catch {
                DispatchQueue.main.async { self.stop(with: .persistence(error)) }
                return
            }
            DispatchQueue.main.async { self.advance(after: page, from: startIndex) }
        }
    }

    private func advance(after page: QueryResult<PhotoDTO>, from startIndex: Int) {
        let next = startIndex + page.items.count
        Preferences.syncStartIndex = next
        onProgress?(Progress(indexed: next, total: max(Preferences.syncTotal, next)))

        guard !isCancelled else {
            stop(with: nil)
            return
        }
        guard page.items.count == SyncEngine.pageSize else {
            Preferences.syncCompleted = true
            Preferences.syncTotal = next
            stop(with: nil)
            return
        }
        requestPage(at: next, includeTotalCount: false)
    }

    private func stop(with error: JellyfinError?) {
        isRunning = false
        onFinish?(error)
    }
}

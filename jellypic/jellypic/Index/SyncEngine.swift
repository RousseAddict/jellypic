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
    private var runToken = 0
    private var pageTask: URLSessionTask?
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
        runToken += 1
        requestPage(at: Preferences.syncStartIndex, includeTotalCount: true)
    }

    func refresh(libraryId: String) {
        guard !isRunning else { return }
        Preferences.syncStartIndex = 0
        Preferences.syncCompleted = false
        start(libraryId: libraryId)
    }

    func cancel() {
        runToken += 1
        pageTask?.cancel()
        pageTask = nil
        isRunning = false
    }

    private func requestPage(at startIndex: Int, includeTotalCount: Bool) {
        let token = runToken
        pageTask = client.photos(libraryId: libraryId,
                                 startIndex: startIndex,
                                 limit: SyncEngine.pageSize,
                                 includeTotalCount: includeTotalCount) { [weak self] result in
            guard let self = self, token == self.runToken else { return }
            self.pageTask = nil
            switch result {
            case .failure(let error):
                self.stop(with: error)
            case .success(let page):
                if includeTotalCount {
                    Preferences.syncTotal = page.totalRecordCount
                }
                self.persist(page, from: startIndex, token: token)
            }
        }
    }

    private func persist(_ page: QueryResult<PhotoDTO>, from startIndex: Int, token: Int) {
        store.upsert(page.items) { [weak self] error in
            guard let self = self, token == self.runToken else { return }
            if let error = error {
                self.stop(with: .persistence(error))
                return
            }
            self.advance(after: page, from: startIndex, token: token)
        }
    }

    private func advance(after page: QueryResult<PhotoDTO>, from startIndex: Int, token: Int) {
        let next = startIndex + page.items.count
        Preferences.syncStartIndex = next
        onProgress?(Progress(indexed: next, total: max(Preferences.syncTotal, next)))

        guard token == runToken else { return }
        guard page.items.count == SyncEngine.pageSize else {
            Preferences.syncCompleted = true
            Preferences.syncTotal = next
            stop(with: nil)
            return
        }
        requestPage(at: next, includeTotalCount: false)
    }

    private func stop(with error: JellyfinError?) {
        pageTask = nil
        isRunning = false
        onFinish?(error)
    }
}

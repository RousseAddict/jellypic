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
    private var syncRunStart: Date?
    private var onCatchUpFinished: (() -> Void)?

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
        syncRunStart = nil
        requestPage(at: Preferences.syncStartIndex, includeTotalCount: true)
    }

    func refresh(libraryId: String) {
        guard !isRunning else { return }
        Preferences.clearSync()
        start(libraryId: libraryId)
    }

    func catchUp(libraryId: String, lookback: TimeInterval = 0, completion: (() -> Void)? = nil) {
        guard !isRunning,
              Preferences.syncCompleted,
              Preferences.syncLibraryId == libraryId else {
            completion?()
            return
        }

        self.libraryId = libraryId
        isRunning = true
        runToken += 1
        onCatchUpFinished = completion

        guard let watermark = Preferences.syncWatermark else {
            seedWatermark(lookback: lookback)
            return
        }
        requestCatchUpPage(at: 0, since: watermark.addingTimeInterval(-lookback), start: nil)
    }

    func cancel() {
        runToken += 1
        pageTask?.cancel()
        pageTask = nil
        isRunning = false
        let finished = onCatchUpFinished
        onCatchUpFinished = nil
        finished?()
    }

    private func requestPage(at startIndex: Int, includeTotalCount: Bool) {
        let token = runToken
        pageTask = client.photos(libraryId: libraryId,
                                 startIndex: startIndex,
                                 limit: SyncEngine.pageSize,
                                 includeTotalCount: includeTotalCount,
                                 minDateLastSaved: nil) { [weak self] result in
            guard let self = self, token == self.runToken else { return }
            self.pageTask = nil
            switch result {
            case .failure(let error):
                self.stop(with: error)
            case .success(let page):
                if includeTotalCount {
                    Preferences.syncTotal = page.totalRecordCount
                }
                if self.syncRunStart == nil {
                    self.syncRunStart = page.serverDate
                }
                self.persist(page, from: startIndex, token: token)
            }
        }
    }

    private func persist(_ page: PhotoPage, from startIndex: Int, token: Int) {
        store.upsert(page.items) { [weak self] error in
            guard let self = self, token == self.runToken else { return }
            if let error = error {
                self.stop(with: .persistence(error))
                return
            }
            self.advance(after: page, from: startIndex, token: token)
        }
    }

    private func seedWatermark(lookback: TimeInterval) {
        let token = runToken
        pageTask = client.photos(libraryId: libraryId,
                                 startIndex: 0,
                                 limit: 1,
                                 includeTotalCount: false,
                                 minDateLastSaved: nil) { [weak self] result in
            guard let self = self, token == self.runToken else { return }
            self.pageTask = nil
            guard case .success(let page) = result, let serverDate = page.serverDate else {
                self.endCatchUp(committing: nil)
                return
            }
            guard lookback > 0 else {
                self.endCatchUp(committing: serverDate)
                return
            }
            SyncEngine.raiseWatermark(to: serverDate)
            self.requestCatchUpPage(at: 0,
                                    since: serverDate.addingTimeInterval(-lookback),
                                    start: serverDate)
        }
    }

    private func requestCatchUpPage(at startIndex: Int, since watermark: Date, start: Date?) {
        let token = runToken
        pageTask = client.photos(libraryId: libraryId,
                                 startIndex: startIndex,
                                 limit: SyncEngine.pageSize,
                                 includeTotalCount: false,
                                 minDateLastSaved: watermark) { [weak self] result in
            guard let self = self, token == self.runToken else { return }
            self.pageTask = nil
            guard case .success(let page) = result else {
                self.endCatchUp(committing: nil)
                return
            }
            let runStart = start ?? page.serverDate
            guard !page.items.isEmpty else {
                self.endCatchUp(committing: runStart)
                return
            }
            self.store.upsert(page.items) { [weak self] error in
                guard let self = self, token == self.runToken else { return }
                guard error == nil else {
                    self.endCatchUp(committing: nil)
                    return
                }
                guard page.items.count == SyncEngine.pageSize else {
                    self.endCatchUp(committing: runStart)
                    return
                }
                self.requestCatchUpPage(at: startIndex + page.items.count,
                                        since: watermark,
                                        start: runStart)
            }
        }
    }

    private func endCatchUp(committing start: Date?) {
        SyncEngine.raiseWatermark(to: start)
        pageTask = nil
        isRunning = false
        let finished = onCatchUpFinished
        onCatchUpFinished = nil
        finished?()
    }

    private static func raiseWatermark(to start: Date?) {
        guard let start = start else { return }
        if let stored = Preferences.syncWatermark, stored >= start { return }
        Preferences.syncWatermark = start
    }

    private func advance(after page: PhotoPage, from startIndex: Int, token: Int) {
        let next = startIndex + page.items.count
        Preferences.syncStartIndex = next
        onProgress?(Progress(indexed: next, total: max(Preferences.syncTotal, next)))

        guard token == runToken else { return }
        guard page.items.count == SyncEngine.pageSize else {
            Preferences.syncCompleted = true
            SyncEngine.raiseWatermark(to: syncRunStart)
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

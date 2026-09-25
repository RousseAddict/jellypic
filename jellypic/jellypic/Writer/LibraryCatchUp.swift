import Foundation
import Photos
import UIKit

enum CatchUpPhase: Int {
    case idle = 0
    case offered = 1
    case running = 2
    case paused = 3
    case finished = 4
    case declined = 5
}

struct CatchUpState {
    var phase: CatchUpPhase = .idle
    var scanned = 0
    var total = 0
    var found = 0
    var lastErrorText: String?
}

final class LibraryCatchUp {

    static let didChangeNotification = Notification.Name("LibraryCatchUpDidChange")

    private enum Key {
        static let phase = "catchUpPhase"
        static let cursor = "catchUpCursor"
        static let cursorIdentifiers = "catchUpCursorIdentifiers"
        static let undatedDone = "catchUpUndatedDone"
        static let scanned = "catchUpScanned"
        static let total = "catchUpTotal"
        static let found = "catchUpFound"
    }

    private static let firstBatch = 25
    private static let batch = 500

    private let client: UploadClient
    private let exporter: AssetExporter
    private let queue: UploadQueue
    private let defaults = UserDefaults.standard

    private var isScanning = false
    private var isHalted = false
    private var runToken = 0
    private var lastErrorText: String?

    var resolveTarget: ((@escaping (String?) -> Void) -> Void)?

    init(client: UploadClient, exporter: AssetExporter, queue: UploadQueue) {
        self.client = client
        self.exporter = exporter
        self.queue = queue

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var state: CatchUpState {
        return CatchUpState(phase: phase,
                            scanned: defaults.integer(forKey: Key.scanned),
                            total: defaults.integer(forKey: Key.total),
                            found: defaults.integer(forKey: Key.found),
                            lastErrorText: lastErrorText)
    }

    func offer(from watermark: Date) {
        defaults.set(watermark, forKey: Key.cursor)
        defaults.removeObject(forKey: Key.cursorIdentifiers)
        defaults.set(false, forKey: Key.undatedDone)
        defaults.set(0, forKey: Key.scanned)
        defaults.set(0, forKey: Key.found)
        defaults.set(remainingCount(), forKey: Key.total)
        setPhase(.offered)
    }

    func begin() {
        isHalted = false
        defaults.set(0, forKey: Key.scanned)
        defaults.set(0, forKey: Key.found)
        defaults.set(remainingCount(), forKey: Key.total)
        scan()
    }

    func decline() {
        setPhase(.declined)
    }

    func resumeIfNeeded() {
        guard !isHalted, phase == .running || phase == .paused else { return }
        scan()
    }

    func suspend() {
        guard isScanning else { return }
        runToken += 1
        isScanning = false
        lastErrorText = nil
        setPhase(.paused)
    }

    func remainingCount() -> Int {
        guard PHPhotoLibrary.authorizationStatus() == .authorized else { return 0 }

        var count = defaults.bool(forKey: Key.undatedDone)
            ? 0
            : LibraryCatchUp.fetch(LibraryCatchUp.undatedPredicate, limit: 0)?.count ?? 0
        if let cursor = defaults.object(forKey: Key.cursor) as? Date {
            count += LibraryCatchUp.fetch(LibraryCatchUp.datedPredicate(upTo: cursor), limit: 0)?.count ?? 0
        }
        return count
    }

    func reset() {
        runToken += 1
        isScanning = false
        isHalted = false
        lastErrorText = nil
        for key in [Key.phase, Key.cursor, Key.cursorIdentifiers, Key.undatedDone,
                    Key.scanned, Key.total, Key.found] {
            defaults.removeObject(forKey: key)
        }
        notifyChanged()
    }

    private var phase: CatchUpPhase {
        return CatchUpPhase(rawValue: defaults.integer(forKey: Key.phase)) ?? .idle
    }

    private func scan() {
        guard !isScanning, let resolveTarget = resolveTarget else { return }
        guard PHPhotoLibrary.authorizationStatus() == .authorized else {
            pause(BackupUploadError.permissionDenied.text)
            return
        }

        isScanning = true
        lastErrorText = nil
        runToken += 1
        setPhase(.running)

        let token = runToken
        resolveTarget { [weak self] targetId in
            guard let self = self, token == self.runToken, self.isScanning else { return }
            guard let targetId = targetId else {
                self.pause("Your server could not be reached")
                return
            }
            self.step(token: token, targetId: targetId, size: LibraryCatchUp.firstBatch)
        }
    }

    private func step(token: Int, targetId: String, size: Int) {
        guard token == runToken, isScanning else { return }

        if !defaults.bool(forKey: Key.undatedDone) {
            let undated = LibraryCatchUp.assets(LibraryCatchUp.undatedPredicate,
                                                limit: LibraryCatchUp.batch,
                                                skipping: [])
            if !undated.isEmpty {
                hashNext(undated, index: 0, keys: [], owners: [:],
                         isDated: false, token: token, targetId: targetId)
                return
            }
            defaults.set(true, forKey: Key.undatedDone)
        }

        guard let cursor = defaults.object(forKey: Key.cursor) as? Date else {
            complete(.finished)
            return
        }

        let assets = LibraryCatchUp.assets(LibraryCatchUp.datedPredicate(upTo: cursor),
                                           limit: size,
                                           skipping: defaults.stringArray(forKey: Key.cursorIdentifiers) ?? [])
        guard !assets.isEmpty else {
            complete(.finished)
            return
        }

        hashNext(assets, index: 0, keys: [], owners: [:],
                 isDated: true, token: token, targetId: targetId)
    }

    private func hashNext(_ assets: [PHAsset],
                          index: Int,
                          keys: [(sha: String, month: String)],
                          owners: [String: String],
                          isDated: Bool,
                          token: Int,
                          targetId: String) {
        guard token == runToken, isScanning else { return }

        guard index < assets.count else {
            ask(keys, owners: owners, consumed: assets, isDated: isDated,
                token: token, targetId: targetId)
            return
        }

        let asset = assets[index]
        exporter.hash(asset) { [weak self] result in
            guard let self = self, token == self.runToken, self.isScanning else { return }

            var keys = keys
            var owners = owners
            if case .success(let sha) = result {
                keys.append((sha: sha, month: AssetExporter.monthKey(for: asset.creationDate)))
                owners[sha] = asset.localIdentifier
            }

            self.defaults.set(self.defaults.integer(forKey: Key.scanned) + 1, forKey: Key.scanned)
            self.notifyChanged()

            self.hashNext(assets, index: index + 1, keys: keys, owners: owners,
                          isDated: isDated, token: token, targetId: targetId)
        }
    }

    private func ask(_ keys: [(sha: String, month: String)],
                     owners: [String: String],
                     consumed: [PHAsset],
                     isDated: Bool,
                     token: Int,
                     targetId: String) {
        guard !keys.isEmpty else {
            advance(consumed, isDated: isDated, token: token, targetId: targetId)
            return
        }

        client.have(keys, targetId: targetId) { [weak self] result in
            guard let self = self, token == self.runToken, self.isScanning else { return }
            switch result {
            case .success(let missing):
                let identifiers = missing.compactMap { owners[$0] }
                if !identifiers.isEmpty {
                    self.queue.enqueue(identifiers, targetId: targetId)
                    self.defaults.set(self.defaults.integer(forKey: Key.found) + identifiers.count,
                                      forKey: Key.found)
                }
                self.advance(consumed, isDated: isDated, token: token, targetId: targetId)
            case .failure(let failure):
                if case .rejected = failure {
                    self.isHalted = true
                }
                self.pause(LibraryCatchUp.pauseText(failure))
            }
        }
    }

    private func advance(_ consumed: [PHAsset], isDated: Bool, token: Int, targetId: String) {
        guard isDated, let date = consumed.last?.creationDate else {
            defaults.set(true, forKey: Key.undatedDone)
            notifyChanged()
            step(token: token, targetId: targetId, size: LibraryCatchUp.batch)
            return
        }

        var skipped = consumed.filter { $0.creationDate == date }.map { $0.localIdentifier }
        if defaults.object(forKey: Key.cursor) as? Date == date {
            skipped += defaults.stringArray(forKey: Key.cursorIdentifiers) ?? []
        }
        defaults.set(date, forKey: Key.cursor)
        defaults.set(skipped, forKey: Key.cursorIdentifiers)
        notifyChanged()
        step(token: token, targetId: targetId, size: LibraryCatchUp.batch)
    }

    private func complete(_ phase: CatchUpPhase) {
        isScanning = false
        setPhase(phase)
    }

    private func pause(_ text: String?) {
        isScanning = false
        lastErrorText = text
        setPhase(.paused)
    }

    private func setPhase(_ phase: CatchUpPhase) {
        defaults.set(phase.rawValue, forKey: Key.phase)
        notifyChanged()
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: LibraryCatchUp.didChangeNotification, object: nil)
    }

    @objc private func applicationWillResignActive() {
        suspend()
    }

    private static func pauseText(_ failure: UploadFailure) -> String {
        switch failure {
        case .unauthorized:
            return BackupUploadError.unauthorized.text
        case .offline, .transient:
            return "Your server did not answer"
        case .rejected(let code), .stopQueue(let code):
            return BackupUploadError.refusalText(code)
        }
    }

    private static let undatedPredicate = NSPredicate(format: "mediaType == %d AND creationDate == nil",
                                                      PHAssetMediaType.image.rawValue)

    private static func datedPredicate(upTo cursor: Date) -> NSPredicate {
        return NSPredicate(format: "mediaType == %d AND creationDate <= %@",
                           PHAssetMediaType.image.rawValue,
                           cursor as NSDate)
    }

    private static func fetch(_ predicate: NSPredicate, limit: Int) -> PHFetchResult<PHAsset>? {
        guard let library = PHAssetCollection.fetchAssetCollections(with: .smartAlbum,
                                                                    subtype: .smartAlbumUserLibrary,
                                                                    options: nil).firstObject else { return nil }
        let options = PHFetchOptions()
        options.predicate = predicate
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        return PHAsset.fetchAssets(in: library, options: options)
    }

    private static func assets(_ predicate: NSPredicate, limit: Int, skipping: [String]) -> [PHAsset] {
        guard let result = fetch(predicate, limit: limit + skipping.count) else { return [] }
        let skipped = Set(skipping)
        var collected: [PHAsset] = []
        result.enumerateObjects { asset, _, stop in
            guard collected.count < limit else {
                stop.pointee = true
                return
            }
            if !skipped.contains(asset.localIdentifier) {
                collected.append(asset)
            }
        }
        return collected
    }
}

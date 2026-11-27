import Foundation
import Photos
import UIKit

struct UploadQueueState {
    var pending = 0
    var inFlight = 0
    var sent = 0
    var duplicates = 0
    var failed = 0
    var isRunning = false
    var isPaused = false
    var stopReason: BackupUploadError?
    var lastErrorText: String?

    var canAutoResume: Bool {
        return pending > 0 && !isRunning && !isPaused && stopReason == nil
    }
}

final class UploadQueue {

    static let didChangeNotification = Notification.Name("UploadQueueDidChange")

    private enum Outcome {
        case stored(created: Bool)
        case failItem(BackupUploadError)
        case retry(BackupUploadError, limit: Int)
        case waitForWiFi(BackupUploadError)
        case halt(BackupUploadError)
    }

    private struct Snapshot: Codable {
        let version: Int
        let targetId: String?
        let pending: [String]
        let picked: [String]?
        let sent: Int
        let duplicates: Int
        let failed: Int
        let paused: Bool
        let lastError: String?
    }

    private struct Slot {
        let token: Int
        var attempts: Int
    }

    private static let version = 1
    private static let backoff: [TimeInterval] = [1, 4, 15]
    private static let persistEvery = 10
    private static let window = 3

    private let client: UploadClient
    private let exporter: AssetExporter
    private let fileURL: URL

    private var pending: [String] = []
    private var picked: Set<String> = []
    private var heldForWiFi: BackupUploadError?
    private var repicked: Set<String> = []
    private var inFlight: [String: Slot] = [:]
    private var targetId: String?
    private var sent = 0
    private var duplicates = 0
    private var failed = 0
    private var lastErrorText: String?
    private var stopReason: BackupUploadError?
    private var isPaused = false
    private var isPumpArmed = false
    private var isReconciling = true

    private var runToken = 0
    private var sincePersist = 0

    init(client: UploadClient, exporter: AssetExporter) {
        self.client = client
        self.exporter = exporter

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent("Uploads", isDirectory: true)
            .appendingPathComponent("queue.json")

        load()

        client.onUploadFinished = { [weak self] identifier, result in
            self?.uploadFinished(identifier, result)
        }
        client.onUploadCancelled = { [weak self] identifier in
            self?.uploadCancelled(identifier)
        }

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillResignActive),
                                               name: UIApplication.willResignActiveNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    var state: UploadQueueState {
        return UploadQueueState(pending: pending.count,
                                inFlight: inFlight.count,
                                sent: sent,
                                duplicates: duplicates,
                                failed: failed,
                                isRunning: isPumpArmed || !inFlight.isEmpty || isReconciling,
                                isPaused: isPaused,
                                stopReason: stopReason,
                                lastErrorText: lastErrorText)
    }

    func adopt(inFlight identifiers: Set<String>) {
        isReconciling = false

        guard !identifiers.isEmpty else {
            notifyChanged()
            run()
            return
        }

        var known = Set(pending)
        for identifier in identifiers where known.insert(identifier).inserted {
            pending.insert(identifier, at: 0)
        }

        arm()
        for identifier in identifiers {
            inFlight[identifier] = Slot(token: runToken, attempts: 0)
        }
        pump(token: runToken)
    }

    func persistNow() {
        persist()
    }

    func enqueue(_ identifiers: [String], targetId: String, picked byHand: Bool) {
        if pending.isEmpty && !isPumpArmed {
            sent = 0
            duplicates = 0
            failed = 0
            lastErrorText = nil
        }

        if byHand {
            putFirst(identifiers)
        } else {
            var known = Set(pending)
            for identifier in identifiers where known.insert(identifier).inserted {
                pending.append(identifier)
            }
        }

        self.targetId = targetId
        isPaused = false
        stopReason = nil
        persist()
        notifyChanged()
        if isPumpArmed {
            pump(token: runToken)
        } else {
            run()
        }
    }

    private func putFirst(_ identifiers: [String]) {
        let sentWithoutCellular = identifiers.filter { inFlight[$0] != nil && !picked.contains($0) }

        var seen: Set<String> = []
        let ahead = identifiers.filter { seen.insert($0).inserted && inFlight[$0] == nil }
        let moved = Set(ahead)
        pending = ahead + pending.filter { !moved.contains($0) }

        picked.formUnion(identifiers)
        repicked.formUnion(sentWithoutCellular)
        client.cancelUploads(for: sentWithoutCellular)
    }

    func resume(target: UploadTarget) {
        guard !isPumpArmed, !pending.isEmpty else { return }
        targetId = target.id
        run()
    }

    func stop() {
        guard isPumpArmed else { return }
        isPaused = true
        finish(reason: nil)
    }

    func clear() {
        let cancelled = Array(inFlight.keys)
        runToken += 1
        isPumpArmed = false
        isPaused = false
        stopReason = nil
        lastErrorText = nil
        inFlight = [:]
        pending = []
        picked = []
        heldForWiFi = nil
        repicked = []
        targetId = nil
        sent = 0
        duplicates = 0
        failed = 0
        persist()
        client.cancelUploads(for: cancelled)
        notifyChanged()
    }

    private func run() {
        guard !isReconciling, !isPumpArmed, !pending.isEmpty, targetId != nil else { return }
        arm()
        pump(token: runToken)
    }

    private func arm() {
        isPumpArmed = true
        isPaused = false
        stopReason = nil
        heldForWiFi = nil
        repicked = []
        runToken += 1
        notifyChanged()
    }

    private func pump(token: Int) {
        guard token == runToken, isPumpArmed, let targetId = targetId else { return }

        while inFlight.keys.filter({ picked.contains($0) }).count < UploadQueue.window,
              let identifier = nextStartable(picked: true) {
            launch(identifier, token: token, targetId: targetId)
        }
        while inFlight.count < UploadQueue.window, let identifier = nextStartable(picked: false) {
            launch(identifier, token: token, targetId: targetId)
        }

        if inFlight.isEmpty {
            finish(reason: pending.isEmpty ? nil : heldForWiFi)
        }
    }

    private func nextStartable(picked wanted: Bool) -> String? {
        guard wanted ? !picked.isEmpty : heldForWiFi == nil else { return nil }
        return pending.first { inFlight[$0] == nil && picked.contains($0) == wanted }
    }

    private func launch(_ identifier: String, token: Int, targetId: String) {
        inFlight[identifier] = Slot(token: token, attempts: 0)
        start(identifier, token: token, targetId: targetId)
    }

    private func schedulePump() {
        let token = runToken
        DispatchQueue.main.async { [weak self] in
            guard let self = self, token == self.runToken else { return }
            self.pump(token: token)
        }
    }

    private func start(_ identifier: String, token: Int, targetId: String) {
        guard let asset = UploadQueue.asset(for: identifier) else {
            let outcome: Outcome = PhotoAccess.current == .full
                ? .failItem(.photoUnavailable)
                : .halt(.permissionDenied)
            DispatchQueue.main.async { [weak self] in
                self?.complete(outcome, identifier: identifier, token: token)
            }
            return
        }

        exporter.export(asset, identifier: identifier) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let failure):
                self.complete(UploadQueue.verdict(failure), identifier: identifier, token: token)
            case .success(let export):
                guard self.client.send(export,
                                       targetId: targetId,
                                       identifier: identifier,
                                       allowsCellular: self.picked.contains(identifier)) else {
                    self.complete(.halt(.notReady), identifier: identifier, token: token)
                    return
                }
            }
        }
    }

    private func uploadFinished(_ identifier: String, _ result: Result<UploadReceipt, UploadFailure>) {
        exporter.discardStaged(for: identifier)
        let outcome: Outcome
        switch result {
        case .success(let receipt):
            outcome = .stored(created: receipt.created)
        case .failure(let failure):
            outcome = UploadQueue.verdict(failure)
        }
        guard inFlight[identifier] != nil else {
            settleUnadopted(outcome, identifier: identifier)
            return
        }
        complete(outcome, identifier: identifier, token: runToken)
    }

    private func settleUnadopted(_ outcome: Outcome, identifier: String) {
        guard let index = pending.firstIndex(of: identifier) else { return }
        switch outcome {
        case .stored(let created):
            if created {
                sent += 1
            } else {
                duplicates += 1
            }
        case .failItem(let error):
            failed += 1
            lastErrorText = error.text
        case .retry, .waitForWiFi, .halt:
            return
        }
        pending.remove(at: index)
        picked.remove(identifier)
        persist()
        notifyChanged()
    }

    private func uploadCancelled(_ identifier: String) {
        exporter.discardStaged(for: identifier)
        guard repicked.remove(identifier) != nil, inFlight.removeValue(forKey: identifier) != nil else { return }
        schedulePump()
    }

    private func complete(_ outcome: Outcome, identifier: String, token: Int) {
        guard token == runToken, let slot = inFlight[identifier], slot.token == token else { return }

        switch outcome {
        case .stored(let created):
            if created {
                sent += 1
            } else {
                duplicates += 1
            }
            retire(identifier)
        case .failItem(let error):
            failed += 1
            lastErrorText = error.text
            retire(identifier)
        case .retry(let error, let limit):
            let attempts = slot.attempts + 1
            guard attempts <= limit, attempts <= UploadQueue.backoff.count else {
                complete(.failItem(error), identifier: identifier, token: token)
                return
            }
            inFlight[identifier] = Slot(token: token, attempts: attempts)
            DispatchQueue.main.asyncAfter(deadline: .now() + UploadQueue.backoff[attempts - 1]) { [weak self] in
                guard let self = self, token == self.runToken, let targetId = self.targetId else { return }
                self.start(identifier, token: token, targetId: targetId)
            }
        case .waitForWiFi(let error):
            let wasSentWithoutCellular = repicked.remove(identifier) != nil || !picked.contains(identifier)
            guard wasSentWithoutCellular else {
                finish(reason: error)
                return
            }
            inFlight.removeValue(forKey: identifier)
            heldForWiFi = error
            schedulePump()
        case .halt(let error):
            finish(reason: error)
        }
    }

    private func retire(_ identifier: String) {
        inFlight.removeValue(forKey: identifier)
        if let index = pending.firstIndex(of: identifier) {
            pending.remove(at: index)
        }
        picked.remove(identifier)
        repicked.remove(identifier)
        sincePersist += 1
        if sincePersist >= UploadQueue.persistEvery {
            persist()
        }
        notifyChanged()
        schedulePump()
    }

    private func finish(reason: BackupUploadError?) {
        let cancelled = Array(inFlight.keys)
        runToken += 1
        isPumpArmed = false
        stopReason = reason
        inFlight = [:]
        persist()
        client.cancelUploads(for: cancelled)
        notifyChanged()
    }

    private static func verdict(_ failure: AssetExportFailure) -> Outcome {
        let error = BackupUploadError.from(failure)
        switch failure {
        case .denied:
            return .halt(error)
        case .noAsset, .noResource, .notLocal:
            return .failItem(error)
        case .write:
            return .retry(error, limit: 1)
        }
    }

    private static func verdict(_ failure: UploadFailure) -> Outcome {
        let error = BackupUploadError.from(failure)
        switch failure {
        case .unauthorized, .stopQueue:
            return .halt(error)
        case .offline:
            return .waitForWiFi(error)
        case .rejected(let code):
            return code == "HASH_MISMATCH" ? .retry(error, limit: 1) : .failItem(error)
        case .transient:
            return .retry(error, limit: UploadQueue.backoff.count)
        }
    }

    private static func asset(for identifier: String) -> PHAsset? {
        return PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    @objc private func applicationWillResignActive() {
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == UploadQueue.version else { return }
        pending = snapshot.pending
        picked = Set(snapshot.picked ?? []).intersection(pending)
        targetId = snapshot.targetId
        sent = snapshot.sent
        duplicates = snapshot.duplicates
        failed = snapshot.failed
        isPaused = snapshot.paused
        lastErrorText = snapshot.lastError
    }

    private func persist() {
        sincePersist = 0

        guard !pending.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }

        let snapshot = Snapshot(version: UploadQueue.version,
                                targetId: targetId,
                                pending: pending,
                                picked: Array(picked),
                                sent: sent,
                                duplicates: duplicates,
                                failed: failed,
                                paused: isPaused,
                                lastError: lastErrorText)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true,
                                                 attributes: nil)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: UploadQueue.didChangeNotification, object: nil)
    }
}

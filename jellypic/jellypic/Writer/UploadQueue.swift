import Foundation
import Photos
import UIKit

struct UploadQueueState {
    var pending = 0
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
        case halt(BackupUploadError)
    }

    private struct Snapshot: Codable {
        let version: Int
        let targetId: String?
        let pending: [String]
        let sent: Int
        let duplicates: Int
        let failed: Int
        let paused: Bool
        let lastError: String?
    }

    private static let version = 1
    private static let backoff: [TimeInterval] = [1, 4, 15]
    private static let persistEvery = 10

    private let client: UploadClient
    private let exporter: AssetExporter
    private let fileURL: URL

    private var pending: [String] = []
    private var targetId: String?
    private var sent = 0
    private var duplicates = 0
    private var failed = 0
    private var lastErrorText: String?
    private var stopReason: BackupUploadError?
    private var isPaused = false
    private var isRunning = false

    private var runToken = 0
    private var attempts = 0
    private var attemptedIdentifier: String?
    private var sincePersist = 0
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid

    init(client: UploadClient, exporter: AssetExporter) {
        self.client = client
        self.exporter = exporter

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent("Uploads", isDirectory: true)
            .appendingPathComponent("queue.json")

        load()

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
                                sent: sent,
                                duplicates: duplicates,
                                failed: failed,
                                isRunning: isRunning,
                                isPaused: isPaused,
                                stopReason: stopReason,
                                lastErrorText: lastErrorText)
    }

    func enqueue(_ identifiers: [String], targetId: String) {
        if pending.isEmpty && !isRunning {
            sent = 0
            duplicates = 0
            failed = 0
            lastErrorText = nil
        }

        var known = Set(pending)
        for identifier in identifiers where known.insert(identifier).inserted {
            pending.append(identifier)
        }

        self.targetId = targetId
        isPaused = false
        stopReason = nil
        persist()
        notifyChanged()
        run()
    }

    func resume(target: UploadTarget) {
        guard !isRunning, !pending.isEmpty else { return }
        targetId = target.id
        run()
    }

    func stop() {
        guard isRunning else { return }
        isPaused = true
        finish(reason: nil)
    }

    func clear() {
        runToken += 1
        isRunning = false
        isPaused = false
        stopReason = nil
        lastErrorText = nil
        attempts = 0
        attemptedIdentifier = nil
        pending = []
        targetId = nil
        sent = 0
        duplicates = 0
        failed = 0
        persist()
        endBackgroundTask()
        notifyChanged()
    }

    private func run() {
        guard !isRunning, !pending.isEmpty, let targetId = targetId else { return }
        isRunning = true
        isPaused = false
        stopReason = nil
        runToken += 1
        beginBackgroundTask()
        notifyChanged()
        step(token: runToken, targetId: targetId)
    }

    private func step(token: Int, targetId: String) {
        guard token == runToken else { return }
        guard let identifier = pending.first else {
            finish(reason: nil)
            return
        }

        if attemptedIdentifier != identifier {
            attemptedIdentifier = identifier
            attempts = 0
        }

        guard let asset = UploadQueue.asset(for: identifier) else {
            complete(.failItem(.photoUnavailable), token: token, targetId: targetId)
            return
        }

        exporter.export(asset) { [weak self] result in
            guard let self = self, token == self.runToken else { return }
            switch result {
            case .failure(let failure):
                self.complete(UploadQueue.verdict(failure), token: token, targetId: targetId)
            case .success(let export):
                self.upload(export, token: token, targetId: targetId)
            }
        }
    }

    private func upload(_ export: AssetExport, token: Int, targetId: String) {
        client.upload(export, targetId: targetId) { [weak self] outcome in
            guard let self = self else { return }
            self.exporter.discard(export)
            guard token == self.runToken else { return }
            switch outcome {
            case .success(let receipt):
                self.complete(.stored(created: receipt.created), token: token, targetId: targetId)
            case .failure(let failure):
                self.complete(UploadQueue.verdict(failure), token: token, targetId: targetId)
            }
        }
    }

    private func complete(_ outcome: Outcome, token: Int, targetId: String) {
        guard token == runToken else { return }
        switch outcome {
        case .stored(let created):
            if created {
                sent += 1
            } else {
                duplicates += 1
            }
            advance(token: token, targetId: targetId)
        case .failItem(let error):
            failed += 1
            lastErrorText = error.text
            advance(token: token, targetId: targetId)
        case .retry(let error, let limit):
            attempts += 1
            guard attempts <= limit, attempts <= UploadQueue.backoff.count else {
                complete(.failItem(error), token: token, targetId: targetId)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + UploadQueue.backoff[attempts - 1]) { [weak self] in
                guard let self = self, token == self.runToken else { return }
                self.step(token: token, targetId: targetId)
            }
        case .halt(let error):
            finish(reason: error)
        }
    }

    private func advance(token: Int, targetId: String) {
        pending.removeFirst()
        attemptedIdentifier = nil
        attempts = 0
        sincePersist += 1
        if sincePersist >= UploadQueue.persistEvery {
            persist()
        }
        notifyChanged()

        DispatchQueue.main.async { [weak self] in
            guard let self = self, token == self.runToken else { return }
            self.step(token: token, targetId: targetId)
        }
    }

    private func finish(reason: BackupUploadError?) {
        runToken += 1
        isRunning = false
        stopReason = reason
        attempts = 0
        attemptedIdentifier = nil
        persist()
        endBackgroundTask()
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
        case .unauthorized, .stopQueue, .offline:
            return .halt(error)
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

    private func beginBackgroundTask() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "JellypicUploads") { [weak self] in
            guard let self = self else { return }
            self.persist()
            self.finish(reason: nil)
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: UploadQueue.didChangeNotification, object: nil)
    }
}

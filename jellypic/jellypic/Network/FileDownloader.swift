import Foundation

final class FileDownloader: NSObject {

    private struct Handlers {
        let fileName: String
        let progress: (Int64, Int64) -> Void
        let completion: (Result<URL, JellyfinError>) -> Void
    }

    private var handlers: [Int: Handlers] = [:]

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }()

    func download(_ request: URLRequest,
                  fileName: String,
                  progress: @escaping (Int64, Int64) -> Void,
                  completion: @escaping (Result<URL, JellyfinError>) -> Void) -> URLSessionTask {
        let task = session.downloadTask(with: request)
        handlers[task.taskIdentifier] = Handlers(fileName: fileName,
                                                 progress: progress,
                                                 completion: completion)
        task.resume()
        return task
    }
}

extension FileDownloader: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        handlers[downloadTask.taskIdentifier]?.progress(totalBytesWritten,
                                                        totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let handlers = handlers.removeValue(forKey: downloadTask.taskIdentifier) else { return }

        if let response = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(response.statusCode) {
            handlers.completion(.failure(response.statusCode == 401
                ? .unauthorized
                : .httpStatus(response.statusCode)))
            return
        }

        let destination = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(handlers.fileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            handlers.completion(.success(destination))
        } catch {
            handlers.completion(.failure(.transport(error)))
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let handlers = handlers.removeValue(forKey: task.taskIdentifier),
              let error = error,
              (error as NSError).code != NSURLErrorCancelled else { return }

        if let urlError = error as? URLError {
            handlers.completion(.failure(.unreachable(urlError)))
        } else {
            handlers.completion(.failure(.transport(error)))
        }
    }
}

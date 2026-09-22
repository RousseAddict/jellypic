import AVFoundation
import AVKit
import UIKit
import VideoToolbox

enum VideoCapabilities {

    static let supportsHEVC: Bool = {
        return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
    }()

    static func deviceProfile() -> [String: Any] {
        var videoCodecs = ["h264", "mpeg4"]
        if supportsHEVC {
            videoCodecs.append("hevc")
        }
        return [
            "MaxStreamingBitrate": 20_000_000,
            "DirectPlayProfiles": [
                [
                    "Type": "Video",
                    "Container": "mp4,m4v,mov",
                    "VideoCodec": videoCodecs.joined(separator: ","),
                    "AudioCodec": "aac,mp3,ac3"
                ]
            ],
            "TranscodingProfiles": [
                [
                    "Type": "Video",
                    "Container": "ts",
                    "Protocol": "hls",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac",
                    "Context": "Streaming",
                    "MinSegments": 1,
                    "BreakOnNonKeyFrames": true
                ]
            ]
        ]
    }
}

final class VideoPlaybackController {

    private let services: AppServices
    private weak var presenter: UIViewController?
    private var task: URLSessionTask?

    var onBusyChanged: ((Bool) -> Void)?

    init(services: AppServices, presenter: UIViewController) {
        self.services = services
        self.presenter = presenter
    }

    deinit {
        task?.cancel()
    }

    func play(itemId: String) {
        guard task == nil else { return }
        onBusyChanged?(true)

        task = services.client.playbackInfo(itemId: itemId,
                                            deviceProfile: VideoCapabilities.deviceProfile()) { [weak self] result in
            guard let self = self else { return }
            self.task = nil
            self.onBusyChanged?(false)

            switch result {
            case .success(let info):
                self.start(itemId: itemId, info: info)
            case .failure:
                self.report(title: "Cannot play this video",
                            message: "The server could not be reached.")
            }
        }
    }

    private func start(itemId: String, info: PlaybackInfoResponse) {
        guard let source = info.mediaSources.first else {
            report(title: "Cannot play this video",
                   message: "The server returned no media source for this item.")
            return
        }

        guard source.supportsDirectPlay == true,
              let url = services.client.directPlayURL(itemId: itemId,
                                                      mediaSourceId: source.id,
                                                      playSessionId: info.playSessionId) else {
            reportConversionNeeded(source)
            return
        }

        present(url)
    }

    private func present(_ url: URL) {
        guard let presenter = presenter else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        presenter.present(controller, animated: true) {
            player.play()
        }
    }

    private func reportConversionNeeded(_ source: MediaSourceDTO) {
        let reasons = source.transcodeReasons
        let detail = reasons.isEmpty
            ? "The server did not say why."
            : "Reported reason: \(reasons.joined(separator: ", "))."
        report(title: "This video needs converting",
               message: "This device cannot play the file as it is stored, so the server would have to convert it. "
                   + "Jellypic does not request that yet.\n\n"
                   + detail)
    }

    private func report(title: String, message: String) {
        guard let presenter = presenter else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        presenter.present(alert, animated: true, completion: nil)
    }
}

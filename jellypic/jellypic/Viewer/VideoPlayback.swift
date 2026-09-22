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

private final class PlayerViewController: AVPlayerViewController {

    var onDismissed: (() -> Void)?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed else { return }
        player?.pause()
        let handler = onDismissed
        onDismissed = nil
        handler?()
    }
}

final class VideoPlaybackController {

    private let services: AppServices
    private weak var presenter: UIViewController?
    private var plans: [String: PlaybackInfoResponse] = [:]
    private var probeTask: URLSessionTask?
    private var playTask: URLSessionTask?

    var onBusyChanged: ((Bool) -> Void)?

    init(services: AppServices, presenter: UIViewController) {
        self.services = services
        self.presenter = presenter
    }

    deinit {
        probeTask?.cancel()
        playTask?.cancel()
    }

    func probe(itemId: String, completion: @escaping (Bool) -> Void) {
        if let plan = plans[itemId] {
            completion(needsConversion(plan))
            return
        }
        probeTask?.cancel()
        probeTask = request(itemId: itemId) { [weak self] plan in
            guard let self = self else { return }
            self.probeTask = nil
            guard let plan = plan else { return }
            completion(self.needsConversion(plan))
        }
    }

    func play(itemId: String) {
        if let plan = plans[itemId] {
            start(itemId: itemId, plan: plan)
            return
        }
        guard playTask == nil else { return }
        onBusyChanged?(true)
        playTask = request(itemId: itemId) { [weak self] plan in
            guard let self = self else { return }
            self.playTask = nil
            self.onBusyChanged?(false)
            guard let plan = plan else {
                self.report(title: "Cannot play this video",
                            message: "The server could not be reached.")
                return
            }
            self.start(itemId: itemId, plan: plan)
        }
    }

    private func request(itemId: String,
                         completion: @escaping (PlaybackInfoResponse?) -> Void) -> URLSessionTask? {
        return services.client.playbackInfo(itemId: itemId,
                                            deviceProfile: VideoCapabilities.deviceProfile()) { [weak self] result in
            switch result {
            case .success(let plan):
                self?.plans[itemId] = plan
                completion(plan)
            case .failure:
                completion(nil)
            }
        }
    }

    private func needsConversion(_ plan: PlaybackInfoResponse) -> Bool {
        guard let source = plan.mediaSources.first else { return false }
        return source.supportsDirectPlay != true
    }

    private func start(itemId: String, plan: PlaybackInfoResponse) {
        guard let source = plan.mediaSources.first else {
            report(title: "Cannot play this video",
                   message: "The server returned no media source for this item.")
            return
        }

        if source.supportsDirectPlay == true,
           let url = services.client.directPlayURL(itemId: itemId,
                                                   mediaSourceId: source.id,
                                                   playSessionId: plan.playSessionId) {
            present(url, itemId: itemId, playSessionId: nil)
            return
        }

        if let path = source.transcodingUrl,
           let url = services.client.transcodedStreamURL(serverPath: path) {
            present(url, itemId: itemId, playSessionId: plan.playSessionId)
            return
        }

        reportUnplayable(source)
    }

    private func present(_ url: URL, itemId: String, playSessionId: String?) {
        guard let presenter = presenter else { return }

        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)

        let player = AVPlayer(url: url)
        let controller = PlayerViewController()
        controller.player = player
        controller.onDismissed = { [weak self] in
            try? AVAudioSession.sharedInstance().setActive(false)
            guard let playSessionId = playSessionId else { return }
            self?.services.client.reportPlaybackStopped(itemId: itemId, playSessionId: playSessionId)
        }
        presenter.present(controller, animated: true) {
            player.play()
        }
    }

    private func reportUnplayable(_ source: MediaSourceDTO) {
        let reasons = source.transcodeReasons
        let detail = reasons.isEmpty
            ? "The server did not say why."
            : "Reported reason: \(reasons.joined(separator: ", "))."
        report(title: "Cannot play this video",
               message: "This device cannot play the file as it is stored, and the server did not offer to "
                   + "convert it.\n\n"
                   + detail)
    }

    private func report(title: String, message: String) {
        guard let presenter = presenter else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        presenter.present(alert, animated: true, completion: nil)
    }
}

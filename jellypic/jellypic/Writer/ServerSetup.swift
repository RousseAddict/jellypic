import Foundation

enum ServerSetupBadge {
    case missing
    case attention
    case ready
}

struct ServerSetupLine {
    let title: String
    let detail: String
    let badge: ServerSetupBadge
}

enum ServerSetupHelp {
    case install
    case finish
    case share

    var title: String {
        switch self {
        case .install:
            return "How to install"
        case .finish:
            return "How to finish setup"
        case .share:
            return "Send setup instructions"
        }
    }
}

struct ServerSetupLink {
    let name: String
    let url: URL
}

struct ServerSetup {

    static let uploadRepository = URL(string: "https://raw.githubusercontent.com/RousseAddict/upload-for-jelly/main/manifest.json")!
    static let heicRepository = URL(string: "https://raw.githubusercontent.com/RousseAddict/heic-for-jelly/main/manifest.json")!

    private static let uploadName = "Upload for Jelly"
    private static let heicName = "HEIC for Jelly"
    private static let uploadPluginId = "f85a21b6831f41bebc520831f45355ab"

    let availability: BackupAvailability
    let heic: HeicStatus
    let isAdministrator: Bool
    let libraryName: String
    let serverURL: URL?

    var needsAttention: Bool {
        return uploadNeedsInstall || uploadNeedsTick || uploadFolderProblem != nil
            || heic == .notInstalled || heicIsOff
    }

    var uploadLine: ServerSetupLine {
        let title = ServerSetup.uploadName
        switch availability {
        case .notInstalled:
            return ServerSetupLine(title: title, detail: "Not installed — needed to send photos", badge: .missing)
        case .incompatible:
            return ServerSetupLine(title: title, detail: "Needs an update", badge: .attention)
        case .notConfigured:
            return ServerSetupLine(title: title, detail: "Installed — “\(libraryName)” is not open yet", badge: .attention)
        case .blocked(let reason):
            return ServerSetupLine(title: title, detail: reason, badge: .missing)
        case .ready:
            return ServerSetupLine(title: title, detail: "Ready", badge: .ready)
        case .unknown:
            return ServerSetupLine(title: title, detail: "Could not check", badge: .attention)
        }
    }

    var heicLine: ServerSetupLine {
        let title = ServerSetup.heicName
        switch heic {
        case .notInstalled:
            return ServerSetupLine(title: title, detail: "Missing or outdated — needed for iPhone photos", badge: .missing)
        case .decoding:
            return ServerSetupLine(title: title, detail: "Ready", badge: .ready)
        case .off("FFMPEG_TOO_OLD"?):
            return ServerSetupLine(title: title, detail: "Your server's ffmpeg is too old", badge: .missing)
        case .off("FFMPEG_MISSING"?):
            return ServerSetupLine(title: title, detail: "Your server has no usable ffmpeg", badge: .missing)
        case .off:
            return ServerSetupLine(title: title, detail: "Installed, but HEIC is off", badge: .missing)
        case .unknown:
            return ServerSetupLine(title: title, detail: "Could not check", badge: .attention)
        }
    }

    var subtitle: String {
        guard isAdministrator else {
            return "Backup needs two plugins. Only your server's administrator can set them up."
        }
        if help == .finish {
            return "One step left before backup works."
        }
        return "Backup needs two plugins on your Jellyfin server."
    }

    var help: ServerSetupHelp {
        guard isAdministrator else { return .share }
        let onlyTheTick = uploadNeedsTick && !uploadNeedsInstall && uploadFolderProblem == nil
            && heic != .notInstalled && !heicIsOff
        return onlyTheTick ? .finish : .install
    }

    var links: [ServerSetupLink] {
        var links: [ServerSetupLink] = []
        if uploadNeedsInstall {
            links.append(ServerSetupLink(name: ServerSetup.uploadName, url: ServerSetup.uploadRepository))
        }
        if heic == .notInstalled {
            links.append(ServerSetupLink(name: ServerSetup.heicName, url: ServerSetup.heicRepository))
        }
        return links
    }

    var steps: [String] {
        var steps: [String] = []
        let missing = links.map { $0.name }

        if !missing.isEmpty {
            steps.append(missing.count == 2
                ? "In Jellyfin, open Plugins › Repositories and add both links."
                : "In Jellyfin, open Plugins › Repositories and add the link.")
            let verb = availability.isIncompatible || heic == .notInstalled ? "install or update" : "install"
            let what = missing.count == 2 ? "both" : missing[0]
            steps.append("In the Catalogue, \(verb) \(what), then restart the server.")
        }
        if uploadNeedsTick {
            steps.append("Open \(ServerSetup.uploadName) and tick “\(libraryName)”.")
        }
        if uploadFolderProblem != nil {
            steps.append("Let Jellyfin write to the folder of “\(libraryName)” on your server.")
        }
        if heicIsOff {
            steps.append(heic == .off("FFMPEG_TOO_OLD") || heic == .off("FFMPEG_MISSING")
                ? "Update your server's ffmpeg to version 7 or later."
                : "Check the server log for \(ServerSetup.heicName), then restart the server.")
        }
        return steps
    }

    var dashboardURL: URL? {
        guard let server = serverURL else { return nil }
        let route: String
        if !links.isEmpty {
            route = "/dashboard/plugins/repositories"
        } else if uploadNeedsTick {
            route = "/dashboard/plugins/\(ServerSetup.uploadPluginId)"
        } else {
            return nil
        }
        guard var components = URLComponents(url: server.appendingPathComponent("web/"),
                                             resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = route
        return components.url
    }

    var shareText: String {
        let host = serverURL?.host ?? "your Jellyfin server"
        var lines = ["To back up photos with Jellypic, the Jellyfin server \(host) needs "
            + "\(ServerSetup.uploadName) and \(ServerSetup.heicName).", ""]
        for (index, step) in steps.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        if !links.isEmpty {
            lines.append("")
            for link in links {
                lines.append("\(link.name): \(link.url.absoluteString)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private var uploadNeedsInstall: Bool {
        switch availability {
        case .notInstalled, .incompatible:
            return true
        case .unknown, .notConfigured, .blocked, .ready:
            return false
        }
    }

    private var uploadNeedsTick: Bool {
        switch availability {
        case .notInstalled, .incompatible, .notConfigured:
            return true
        case .unknown, .blocked, .ready:
            return false
        }
    }

    private var uploadFolderProblem: String? {
        guard case .blocked(let reason) = availability else { return nil }
        return reason
    }

    private var heicIsOff: Bool {
        guard case .off = heic else { return false }
        return true
    }
}

private extension BackupAvailability {

    var isIncompatible: Bool {
        guard case .incompatible = self else { return false }
        return true
    }
}

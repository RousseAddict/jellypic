import UIKit
import Security

final class AppServices {

    static let shared = AppServices()
    static let sessionExpiredNotification = Notification.Name("AppServicesSessionExpired")

    let authStore: AuthStore
    let client: JellyfinAPI
    let store: PhotoStore
    let sync: SyncEngine
    let images: ImageLoader
    let upload: UploadService

    private init() {
        let authStore = AuthStore()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let identity = DeviceIdentity(client: "JellyPic",
                                      device: UIDevice.current.name,
                                      deviceId: authStore.deviceId,
                                      version: version)

        let client = JellyfinClient(identity: identity)
        client.credentials = authStore.credentials
        client.cachedImageBaseURL = authStore.session?.baseURL

        let store = CoreDataPhotoStore()

        let upload = JellyfinUploadService(identity: identity)
        upload.credentials = authStore.credentials

        self.authStore = authStore
        self.client = client
        self.store = store
        self.sync = SyncEngine(client: client, store: store)
        self.images = ImageLoader(client: client)
        self.upload = upload

        client.onTokenRejected = { [weak self] in self?.expireSession() }
        images.onUnauthorized = { [weak self] in self?.expireSession() }
        upload.onTokenRejected = { [weak self] in self?.expireSession() }
    }

    var hasSession: Bool {
        return authStore.session != nil
    }

    var isSessionExpired: Bool {
        return hasSession && authStore.credentials == nil
    }

    func signIn(with result: AuthenticationResult, baseURL: URL) -> OSStatus {
        let previous = authStore.session
        let credentials = JellyfinCredentials(baseURL: baseURL,
                                              accessToken: result.accessToken,
                                              userId: result.user.id,
                                              serverId: result.serverId)

        let status = authStore.save(credentials, username: result.user.name)
        guard status == errSecSuccess else { return status }

        if let previous = previous, previous.userId != credentials.userId {
            store.reset()
            images.clearCaches()
            Preferences.clearLibrary()
        }

        client.credentials = credentials
        client.cachedImageBaseURL = baseURL
        upload.credentials = credentials
        return status
    }

    func revalidateSession() {
        guard authStore.credentials != nil else { return }
        client.libraries { _ in }
    }

    func expireSession() {
        guard isSessionExpired == false, hasSession else { return }
        sync.cancel()
        authStore.clearToken()
        client.credentials = nil
        upload.credentials = nil
        NotificationCenter.default.post(name: AppServices.sessionExpiredNotification, object: nil)
    }

    func signOut(completion: @escaping () -> Void) {
        sync.cancel()
        client.logout { [weak self] _ in
            guard let self = self else { return }
            self.authStore.clear()
            self.client.credentials = nil
            self.client.cachedImageBaseURL = nil
            self.upload.credentials = nil
            self.upload.reset()
            self.store.reset()
            self.images.clearCaches()
            Preferences.clearLibrary()
            completion()
        }
    }
}

import UIKit
import Security

final class AppServices {

    static let shared = AppServices()

    let authStore: AuthStore
    let client: JellyfinAPI
    let store: PhotoStore
    let sync: SyncEngine

    private init() {
        let authStore = AuthStore()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let identity = DeviceIdentity(client: "JellyPic",
                                      device: UIDevice.current.name,
                                      deviceId: authStore.deviceId,
                                      version: version)

        let client = JellyfinClient(identity: identity)
        client.credentials = authStore.credentials

        let store = PhotoStore()

        self.authStore = authStore
        self.client = client
        self.store = store
        self.sync = SyncEngine(client: client, store: store)
    }

    func signIn(with result: AuthenticationResult, baseURL: URL) -> OSStatus {
        let credentials = JellyfinCredentials(baseURL: baseURL,
                                              accessToken: result.accessToken,
                                              userId: result.user.id,
                                              serverId: result.serverId)
        let status = authStore.save(credentials)
        client.credentials = credentials
        return status
    }

    func signOut(completion: @escaping () -> Void) {
        sync.cancel()
        client.logout { [weak self] _ in
            guard let self = self else { return }
            self.authStore.clear()
            self.client.credentials = nil
            self.store.reset()
            Preferences.clearLibrary()
            completion()
        }
    }
}

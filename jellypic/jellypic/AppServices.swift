import UIKit

final class AppServices {

    static let shared = AppServices()

    let authStore: AuthStore
    let client: JellyfinAPI

    private init() {
        let authStore = AuthStore()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let identity = DeviceIdentity(client: "JellyPic",
                                      device: UIDevice.current.name,
                                      deviceId: authStore.deviceId,
                                      version: version)

        let client = JellyfinClient(identity: identity)
        client.credentials = authStore.credentials

        self.authStore = authStore
        self.client = client
    }

    func signIn(with result: AuthenticationResult, baseURL: URL) {
        let credentials = JellyfinCredentials(baseURL: baseURL,
                                              accessToken: result.accessToken,
                                              userId: result.user.id,
                                              serverId: result.serverId)
        authStore.save(credentials)
        client.credentials = credentials
    }

    func signOut(completion: @escaping () -> Void) {
        client.logout { [weak self] _ in
            guard let self = self else { return }
            self.authStore.clear()
            self.client.credentials = nil
            Preferences.clearLibrary()
            completion()
        }
    }
}

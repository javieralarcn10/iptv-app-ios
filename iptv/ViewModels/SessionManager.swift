import Foundation
import Observation

@Observable
final class SessionManager {
    private(set) var credentials: XtreamCredentials?

    var isLoggedIn: Bool { credentials != nil }

    init() {
        credentials = CredentialStore.shared.load()
        if let creds = credentials {
            XtreamAPIService.shared.configure(with: creds)
        }
    }

    func login(serverURL: String, username: String, password: String) async throws {
        let response = try await XtreamAPIService.shared.authenticate(
            serverURL: serverURL,
            username: username,
            password: password
        )
        let liveFormats = response.userInfo?.allowedOutputFormats?
            .map { $0.lowercased() } ?? []
        let liveExtension = liveFormats.first { $0 == "ts" }
            ?? liveFormats.first { $0 == "m3u8" }
        let creds = XtreamCredentials(
            serverURL: serverURL,
            username: username,
            password: password,
            liveOutputExtension: liveExtension ?? "ts"
        )
        CredentialStore.shared.save(creds)
        XtreamAPIService.shared.configure(with: creds)
        credentials = creds
    }

    func logout() {
        CredentialStore.shared.delete()
        XtreamAPIService.shared.clearCredentials()
        LivePlaylistStore.shared.clear()
        MovieStore.shared.clear()
        SeriesStore.shared.clear()
        credentials = nil
    }
}

import Foundation

enum XtreamError: LocalizedError {
    case invalidURL
    case authFailed
    case networkError(Error)
    case decodingError(Error)
    case noCredentials

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "URL del servidor no válida"
        case .authFailed:        return "Usuario o contraseña incorrectos"
        case .noCredentials:     return "No hay sesión activa"
        case .networkError(let e): return "Error de red: \(e.localizedDescription)"
        case .decodingError(let e): return "Error procesando respuesta: \(e.localizedDescription)"
        }
    }
}

final class XtreamAPIService {
    static let shared = XtreamAPIService()

    private var credentials: XtreamCredentials?
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    func configure(with credentials: XtreamCredentials) {
        self.credentials = credentials
    }

    func clearCredentials() {
        credentials = nil
    }

    // MARK: - Auth

    func authenticate(serverURL: String, username: String, password: String) async throws -> XtreamAuthResponse {
        let url = try apiURL(serverURL: serverURL, username: username, password: password, action: nil)
        let data = try await get(url: url)
        let response = try decode(XtreamAuthResponse.self, from: data)
        guard response.userInfo?.auth == 1 else {
            throw XtreamError.authFailed
        }
        return response
    }

    // MARK: - Content

    func getLiveStreams() async throws -> [LiveStream] {
        return try await fetchList(action: "get_live_streams")
    }

    func getLiveCategories() async throws -> [LiveCategory] {
        return try await fetchList(action: "get_live_categories")
    }

    func getVODStreams() async throws -> [VODStream] {
        return try await fetchList(action: "get_vod_streams")
    }

    func getSeries() async throws -> [Series] {
        return try await fetchList(action: "get_series")
    }

    func getSeriesInfo(seriesId: Int) async throws -> SeriesInfoResponse {
        let url = try currentAPIURL(action: "get_series_info", extra: "&series_id=\(seriesId)")
        let data = try await get(url: url)
        return try decode(SeriesInfoResponse.self, from: data)
    }

    // MARK: - Stream URLs

    func liveURL(for stream: LiveStream) throws -> URL {
        let creds = try requireCredentials()
        let ext = preferredLiveExtension(from: creds.liveOutputExtension)
        return try streamURL(base: creds.serverURL, type: "live", user: creds.username,
                             pass: creds.password, id: "\(stream.streamId)", ext: ext)
    }

    func vodURL(for vod: VODStream) throws -> URL {
        let creds = try requireCredentials()
        let ext = vod.containerExtension ?? "mp4"
        return try streamURL(base: creds.serverURL, type: "movie", user: creds.username,
                             pass: creds.password, id: "\(vod.streamId)", ext: ext)
    }

    func episodeURL(episodeId: String, ext: String) throws -> URL {
        let creds = try requireCredentials()
        return try streamURL(base: creds.serverURL, type: "series", user: creds.username,
                             pass: creds.password, id: episodeId, ext: ext)
    }

    // MARK: - Private helpers

    private func fetchList<T: Decodable>(action: String) async throws -> T {
        let url = try currentAPIURL(action: action)
        let data = try await get(url: url)
        return try decode(T.self, from: data)
    }

    private func get(url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw XtreamError.authFailed
            }
            return data
        } catch let e as XtreamError {
            throw e
        } catch {
            throw XtreamError.networkError(error)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw XtreamError.decodingError(error)
        }
    }

    private func requireCredentials() throws -> XtreamCredentials {
        guard let creds = credentials else { throw XtreamError.noCredentials }
        return creds
    }

    private func preferredLiveExtension(from storedExtension: String?) -> String {
        let ext = storedExtension?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // IPTV providers often advertise HLS, but their TS endpoint is usually the
        // most reliable path for live channels in VLCKit. PlaybackController can
        // still fall back to m3u8 if TS is not available for this account.
        if ext == nil || ext == "m3u8" || ext?.isEmpty == true {
            return "ts"
        }
        return ext ?? "ts"
    }

    private func currentAPIURL(action: String, extra: String = "") throws -> URL {
        let creds = try requireCredentials()
        return try apiURL(serverURL: creds.serverURL, username: creds.username,
                          password: creds.password, action: action, extra: extra)
    }

    private func apiURL(serverURL: String, username: String, password: String,
                        action: String?, extra: String = "") throws -> URL {
        let base = serverURL.trimmingCharacters(in: .init(charactersIn: "/"))
        guard var components = URLComponents(string: "\(base)/player_api.php") else {
            throw XtreamError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        if let action {
            queryItems.append(URLQueryItem(name: "action", value: action))
        }
        if !extra.isEmpty,
           let extraComponents = URLComponents(string: "https://example.com?\(extra.dropFirst())"),
           let extraItems = extraComponents.queryItems {
            queryItems.append(contentsOf: extraItems)
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw XtreamError.invalidURL }
        return url
    }

    private func streamURL(base: String, type: String, user: String,
                           pass: String, id: String, ext: String) throws -> URL {
        let b = base.trimmingCharacters(in: .init(charactersIn: "/"))
        guard let user = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let pass = pass.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(b)/\(type)/\(user)/\(pass)/\(id).\(ext)") else {
            throw XtreamError.invalidURL
        }
        return url
    }
}

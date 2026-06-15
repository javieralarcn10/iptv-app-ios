import Foundation

struct XtreamCredentials: Codable, Sendable {
    let serverURL: String
    let username: String
    let password: String
    let liveOutputExtension: String?
}

struct XtreamAuthResponse: Codable, Sendable {
    struct UserInfo: Codable, Sendable {
        let auth: Int?
        let status: String?
        let expiryDate: String?
        let maxConnections: String?
        let activeCons: String?
        let createdAt: String?
        let isTrial: String?
        let allowedOutputFormats: [String]?

        enum CodingKeys: String, CodingKey {
            case auth, status
            case expiryDate = "exp_date"
            case maxConnections = "max_connections"
            case activeCons = "active_cons"
            case createdAt = "created_at"
            case isTrial = "is_trial"
            case allowedOutputFormats = "allowed_output_formats"
        }
    }
    let userInfo: UserInfo?
    enum CodingKeys: String, CodingKey {
        case userInfo = "user_info"
    }
}

struct LiveStream: Codable, Identifiable, Sendable {
    let streamId: Int
    let name: String
    let streamIcon: String?
    let categoryId: String?

    var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryId = "category_id"
    }
}

struct LiveCategory: Codable, Identifiable, Sendable {
    let categoryId: String
    let categoryName: String
    let parentId: String?

    var id: String { categoryId }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case parentId = "parent_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryId = try container.decodeFlexibleString(forKey: .categoryId)
        categoryName = try container.decode(String.self, forKey: .categoryName)
        parentId = try container.decodeFlexibleStringIfPresent(forKey: .parentId)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        return try decode(String.self, forKey: key)
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

struct VODStream: Codable, Identifiable, Sendable {
    let streamId: Int
    let name: String
    let streamIcon: String?
    let containerExtension: String?
    let categoryId: String?

    var id: Int { streamId }

    enum CodingKeys: String, CodingKey {
        case streamId = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case containerExtension = "container_extension"
        case categoryId = "category_id"
    }
}

struct Series: Codable, Identifiable, Sendable {
    let seriesId: Int
    let name: String
    let cover: String?
    let plot: String?
    let genre: String?
    let categoryId: String?

    var id: Int { seriesId }

    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case name
        case cover
        case plot
        case genre
        case categoryId = "category_id"
    }
}

struct SeriesInfoResponse: Codable, Sendable {
    struct Info: Codable, Sendable {
        let name: String?
        let cover: String?
        let plot: String?
    }
    let info: Info?
    let episodes: [String: [Episode]]?
}

struct Episode: Codable, Identifiable, Sendable {
    let id: String
    let episodeNum: Int?
    let title: String?
    let containerExtension: String?
    let season: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case episodeNum = "episode_num"
        case title
        case containerExtension = "container_extension"
        case season
    }
}

enum MediaSection: Hashable, Sendable {
    case live, movies, series

    var title: String {
        switch self {
        case .live: return "Live TV"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }

    var systemImage: String {
        switch self {
        case .live: return "antenna.radiowaves.left.and.right"
        case .movies: return "film"
        case .series: return "tv"
        }
    }
}

struct PlayableItem: Identifiable, Sendable {
    let id: Int
    let name: String
    let url: URL
    let thumbnailURL: URL?
    var isLive: Bool = false
}

struct LivePlaylistCachePayload: Sendable {
    let categories: [LiveCategory]
    let streams: [LiveStream]
    let lastUpdated: Date
}

nonisolated extension LivePlaylistCachePayload: Codable {}

struct MovieCachePayload: Sendable {
    let streams: [VODStream]
    let lastUpdated: Date
}

nonisolated extension MovieCachePayload: Codable {}

struct SeriesCachePayload: Sendable {
    let series: [Series]
    let lastUpdated: Date
}

nonisolated extension SeriesCachePayload: Codable {}

enum CatalogSearch {
    static func normalizedQuery(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matches(_ name: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return name.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}

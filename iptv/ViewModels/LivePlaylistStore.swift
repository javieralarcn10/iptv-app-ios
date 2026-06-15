import Foundation

@MainActor
@Observable
final class LivePlaylistStore {
    static let shared = LivePlaylistStore()

    private(set) var categories: [LiveCategory] = []
    private(set) var streams: [LiveStream] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var lastUpdated: Date?

    private var hasLoaded = false

    /// Precomputed stream count per categoryId — avoids O(categories × streams) in UI.
    var streamCountByCategory: [String: Int] {
        var counts: [String: Int] = [:]
        for stream in streams {
            if let catId = stream.categoryId {
                counts[catId, default: 0] += 1
            }
        }
        return counts
    }

    private init() {}

    /// Loads from disk cache if available; only fetches from network when no cache exists.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if loadFromDisk() {
            hasLoaded = true
            return
        }
        await refresh()
    }

    /// Always fetches fresh data from the network and updates the disk cache.
    func refresh() async {
        isLoading = true
        error = nil
        do {
            async let loadedCategories = XtreamAPIService.shared.getLiveCategories()
            async let loadedStreams = XtreamAPIService.shared.getLiveStreams()
            categories = try await loadedCategories
            streams = try await loadedStreams
            lastUpdated = Date()
            hasLoaded = true
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        categories = []
        streams = []
        error = nil
        lastUpdated = nil
        hasLoaded = false
        clearDiskCache()
    }

    // MARK: - Disk cache
    // Stored in DocumentsDirectory so iOS never purges it — playlist persists indefinitely.

    private struct CachePayload: Codable {
        let categories: [LiveCategory]
        let streams: [LiveStream]
        let lastUpdated: Date
    }

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("live_playlist_cache.json")
    }

    private func saveToDisk() {
        guard let url = cacheURL, let date = lastUpdated else { return }
        do {
            let data = try JSONEncoder().encode(CachePayload(categories: categories, streams: streams, lastUpdated: date))
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return false }
        categories = payload.categories
        streams = payload.streams
        lastUpdated = payload.lastUpdated
        return true
    }

    private func clearDiskCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

import Foundation

@MainActor
@Observable
final class MovieStore {
    static let shared = MovieStore()

    private(set) var streams: [VODStream] = []
    private(set) var items: [PlayableItem] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var lastUpdated: Date?

    private var hasLoaded = false

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
            streams = try await XtreamAPIService.shared.getVODStreams()
            rebuildItems()
            lastUpdated = Date()
            hasLoaded = true
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        streams = []
        items = []
        error = nil
        lastUpdated = nil
        hasLoaded = false
        clearDiskCache()
    }

    /// PlayableItems are derived once (not on every view update) so building the
    /// stream URLs for very large catalogs doesn't run during scrolling.
    private func rebuildItems() {
        items = streams.compactMap { v in
            guard let url = try? XtreamAPIService.shared.vodURL(for: v) else { return nil }
            return PlayableItem(
                id: v.streamId,
                name: v.name,
                url: url,
                thumbnailURL: v.streamIcon.flatMap { URL(string: $0) }
            )
        }
    }

    // MARK: - Disk cache

    private struct CachePayload: Codable {
        let streams: [VODStream]
        let lastUpdated: Date
    }

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("vod_cache.json")
    }

    private func saveToDisk() {
        guard let url = cacheURL, let date = lastUpdated else { return }
        do {
            let data = try JSONEncoder().encode(CachePayload(streams: streams, lastUpdated: date))
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return false }
        streams = payload.streams
        lastUpdated = payload.lastUpdated
        rebuildItems()
        return true
    }

    private func clearDiskCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

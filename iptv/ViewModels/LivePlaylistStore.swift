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
    private(set) var streamCountByCategory: [String: Int] = [:]

    private var hasLoaded = false
    private var streamsByCategory: [String: [LiveStream]] = [:]

    private init() {}

    /// Loads from disk cache if available; only fetches from network when no cache exists.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        isLoading = true
        error = nil
        if await loadFromDisk() {
            hasLoaded = true
            isLoading = false
            return
        }
        isLoading = false
        await refresh()
    }

    /// Always fetches fresh data from the network and updates the disk cache.
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        do {
            async let loadedCategories = XtreamAPIService.shared.getLiveCategories()
            async let loadedStreams = XtreamAPIService.shared.getLiveStreams()
            categories = try await loadedCategories
            streams = try await loadedStreams
            rebuildDerivedData()
            lastUpdated = Date()
            hasLoaded = true
            await saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        categories = []
        streams = []
        streamCountByCategory = [:]
        streamsByCategory = [:]
        error = nil
        lastUpdated = nil
        hasLoaded = false
        clearDiskCache()
    }

    func streams(for categoryId: String?) -> [LiveStream] {
        guard let categoryId else { return streams }
        return streamsByCategory[categoryId] ?? []
    }

    private func rebuildDerivedData() {
        var counts: [String: Int] = [:]
        var grouped: [String: [LiveStream]] = [:]

        counts.reserveCapacity(categories.count)
        grouped.reserveCapacity(categories.count)

        for stream in streams {
            guard let categoryId = stream.categoryId else { continue }
            counts[categoryId, default: 0] += 1
            grouped[categoryId, default: []].append(stream)
        }

        streamCountByCategory = counts
        streamsByCategory = grouped
    }

    // MARK: - Disk cache
    // Stored in DocumentsDirectory so iOS never purges it — playlist persists indefinitely.

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("live_playlist_cache.json")
    }

    private func saveToDisk() async {
        guard let url = cacheURL, let date = lastUpdated else { return }
        let payload = LivePlaylistCachePayload(categories: categories, streams: streams, lastUpdated: date)
        await Task.detached(priority: .utility, operation: {
            do {
                let data = try JSONEncoder().encode(payload)
                try data.write(to: url, options: .atomic)
            } catch {}
        }).value
    }

    @discardableResult
    private func loadFromDisk() async -> Bool {
        guard let url = cacheURL else { return false }
        guard let payload = await Task.detached(priority: .userInitiated, operation: { () -> LivePlaylistCachePayload? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(LivePlaylistCachePayload.self, from: data)
        }).value else { return false }
        categories = payload.categories
        streams = payload.streams
        rebuildDerivedData()
        lastUpdated = payload.lastUpdated
        return true
    }

    private func clearDiskCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}


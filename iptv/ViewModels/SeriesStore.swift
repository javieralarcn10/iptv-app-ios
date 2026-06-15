import Foundation

@MainActor
@Observable
final class SeriesStore {
    static let shared = SeriesStore()

    private(set) var series: [Series] = []
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
            series = try await XtreamAPIService.shared.getSeries()
            lastUpdated = Date()
            hasLoaded = true
            saveToDisk()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func clear() {
        series = []
        error = nil
        lastUpdated = nil
        hasLoaded = false
        clearDiskCache()
    }

    // MARK: - Disk cache

    private struct CachePayload: Codable {
        let series: [Series]
        let lastUpdated: Date
    }

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("series_cache.json")
    }

    private func saveToDisk() {
        guard let url = cacheURL, let date = lastUpdated else { return }
        do {
            let data = try JSONEncoder().encode(CachePayload(series: series, lastUpdated: date))
            try data.write(to: url, options: .atomic)
        } catch {}
    }

    @discardableResult
    private func loadFromDisk() -> Bool {
        guard let url = cacheURL,
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return false }
        series = payload.series
        lastUpdated = payload.lastUpdated
        return true
    }

    private func clearDiskCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

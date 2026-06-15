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
            series = try await XtreamAPIService.shared.getSeries()
            lastUpdated = Date()
            hasLoaded = true
            await saveToDisk()
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

    private var cacheURL: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("series_cache.json")
    }

    private func saveToDisk() async {
        guard let url = cacheURL, let date = lastUpdated else { return }
        let payload = SeriesCachePayload(series: series, lastUpdated: date)
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
        guard let payload = await Task.detached(priority: .userInitiated, operation: { () -> SeriesCachePayload? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SeriesCachePayload.self, from: data)
        }).value else { return false }
        series = payload.series
        lastUpdated = payload.lastUpdated
        return true
    }

    private func clearDiskCache() {
        guard let url = cacheURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}


import SwiftUI
import ImageIO
import UIKit

/// In-memory cache of already-decoded (and downsampled) thumbnails.
/// Storing small downsampled images keeps memory bounded even when the user
/// scrolls through tens of thousands of rows.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    /// Tracks in-flight downloads so concurrent rows requesting the same URL
    /// reuse a single task instead of spawning duplicates.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 48 * 1024 * 1024 // ~48 MB of decoded pixels

        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "thumbnail_cache"
        )
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await ThumbnailCache.shared.clearMemory()
            }
        }
    }

    func cachedImage(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    /// Returns a downsampled thumbnail, coalescing duplicate requests.
    func image(for url: URL, maxPixelSize: CGFloat, scale: CGFloat) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return await task.value
        }

        let session = self.session
        let task = Task<UIImage?, Never>.detached(priority: .utility) {
            guard let (data, _) = try? await session.data(from: url) else { return nil }
            return ThumbnailCache.downsample(data: data, maxPixelSize: maxPixelSize, scale: scale)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            cache.setObject(image, forKey: url as NSURL, cost: cost)
        }
        return image
    }

    private func clearMemory() {
        cache.removeAllObjects()
    }

    /// Decodes the image at a reduced resolution using ImageIO so we never hold
    /// full-size bitmaps in memory for a tiny thumbnail slot.
    private static func downsample(data: Data, maxPixelSize: CGFloat, scale: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let maxDimension = maxPixelSize * scale
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
    }
}

/// Drop-in replacement for `AsyncImage` tuned for long lists: it caches decoded
/// thumbnails, downsamples to the display size, coalesces duplicate downloads,
/// and cancels work automatically when a row is recycled (via `.task(id:)`).
struct CachedThumbnail<Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: CGFloat
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        if let cached = await ThumbnailCache.shared.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        let loaded = await ThumbnailCache.shared.image(
            for: url,
            maxPixelSize: maxPixelSize,
            scale: displayScale
        )
        if !Task.isCancelled {
            image = loaded
        }
    }
}
